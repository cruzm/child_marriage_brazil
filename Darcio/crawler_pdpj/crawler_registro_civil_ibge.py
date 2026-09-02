#!/usr/bin/env python3
"""Baixa e audita os arquivos publicos de casamentos do Registro Civil/IBGE.

Este adaptador preserva os padroes uteis dos crawlers DataJud/PDPJ do projeto
(checkpoint, retentativas, gravacao atomica, validacao e manifesto), mas usa o
catalogo HTTPS oficial do IBGE. O catalogo publico contem *tabelas de
resultados*, nao registros individuais. O script registra essa classificacao
explicitamente para impedir que os arquivos sejam tratados como microdados.

Exemplos:
    python crawler_registro_civil_ibge.py --probe-only
    python crawler_registro_civil_ibge.py --years 2024 --dry-run
    python crawler_registro_civil_ibge.py --years 2013:2024
"""

from __future__ import annotations

import argparse
import csv
import hashlib
import json
import logging
import os
import re
import sys
import time
import unicodedata
import zipfile
from dataclasses import asdict, dataclass
from datetime import datetime, timezone
from html.parser import HTMLParser
from pathlib import Path, PurePosixPath
from typing import Iterable
from urllib.error import HTTPError, URLError
from urllib.parse import unquote, urljoin, urlparse
from urllib.request import Request, urlopen


ROOT_URL = "https://ftp.ibge.gov.br/Registro_Civil/"
RESULTS_URL = urljoin(ROOT_URL, "Tabelas_de_Resultados/")
CONFIDENTIALITY_URL = (
    "https://biblioteca.ibge.gov.br/visualizacao/livros/liv101636.pdf"
)
SAR_URL = (
    "https://www.gov.br/pt-br/servicos/"
    "solicitacao-de-acesso-a-sala-de-dados-restritos"
)
DEFAULT_OUTPUT_DIR = Path(__file__).resolve().parent / "dados_registro_civil_publico"
DEFAULT_YEARS = tuple(range(2013, 2025))
FORMAT_PREFERENCE = ("xlsx", "xls", "ods")
USER_AGENT = "child-marriage-brazil/registro-civil-public-crawler/1.0"


class CrawlerError(RuntimeError):
    """Falha controlada de catalogo, download ou validacao."""


class _LinkParser(HTMLParser):
    def __init__(self) -> None:
        super().__init__()
        self.links: list[str] = []

    def handle_starttag(self, tag: str, attrs: list[tuple[str, str | None]]) -> None:
        if tag.lower() != "a":
            return
        href = dict(attrs).get("href")
        if href:
            self.links.append(href)


@dataclass(frozen=True)
class Asset:
    year: int
    file_format: str
    source_url: str
    filename: str
    catalog_url: str


@dataclass
class ManifestRow:
    year: int
    status: str
    data_level: str
    file_format: str
    source_url: str
    local_path: str
    size_bytes: int | None
    sha256: str
    archive_members: int | None
    spreadsheet_members: int | None
    checkpoint: str
    checked_at_utc: str
    note: str


def _utc_now() -> str:
    return datetime.now(timezone.utc).isoformat(timespec="seconds")


def _fold_text(value: str) -> str:
    normalized = unicodedata.normalize("NFKD", value)
    return "".join(char for char in normalized if not unicodedata.combining(char)).lower()


def parse_years(specification: str) -> list[int]:
    """Aceita ``2024``, ``2013:2024`` ou ``2013,2019,2024``."""
    years: set[int] = set()
    for token in specification.split(","):
        token = token.strip()
        if not token:
            continue
        if ":" in token:
            pieces = token.split(":")
            if len(pieces) != 2:
                raise argparse.ArgumentTypeError(f"Intervalo de anos invalido: {token}")
            try:
                start, end = (int(piece) for piece in pieces)
            except ValueError as exc:
                raise argparse.ArgumentTypeError(f"Ano invalido: {token}") from exc
            if start > end:
                raise argparse.ArgumentTypeError(f"Intervalo decrescente: {token}")
            years.update(range(start, end + 1))
        else:
            try:
                years.add(int(token))
            except ValueError as exc:
                raise argparse.ArgumentTypeError(f"Ano invalido: {token}") from exc
    if not years:
        raise argparse.ArgumentTypeError("Informe ao menos um ano")
    if min(years) < 1974 or max(years) > datetime.now().year:
        raise argparse.ArgumentTypeError(
            "Anos devem estar entre 1974 e o ano corrente"
        )
    return sorted(years)


def extract_links(html: str) -> list[str]:
    parser = _LinkParser()
    parser.feed(html)
    return parser.links


def select_marriage_archive(links: Iterable[str]) -> str | None:
    """Seleciona a revisao mais recente anunciada para as tabelas 04."""
    candidates = []
    for href in links:
        filename = unquote(PurePosixPath(urlparse(href).path).name)
        if re.fullmatch(r"04casamentos[^/]*\.zip", filename, flags=re.IGNORECASE):
            candidates.append(href)
    if not candidates:
        return None
    return sorted(candidates, key=lambda item: _fold_text(unquote(item)))[-1]


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as source:
        for chunk in iter(lambda: source.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def validate_archive(path: Path) -> dict[str, int]:
    if not path.is_file() or path.stat().st_size == 0:
        raise CrawlerError(f"Arquivo ausente ou vazio: {path}")
    if not zipfile.is_zipfile(path):
        raise CrawlerError(f"Resposta nao e um ZIP valido: {path}")

    allowed_spreadsheets = {".xlsx", ".xls", ".ods"}
    with zipfile.ZipFile(path) as archive:
        members = [member for member in archive.infolist() if not member.is_dir()]
        unsafe = []
        for member in members:
            member_path = PurePosixPath(member.filename)
            if member_path.is_absolute() or ".." in member_path.parts:
                unsafe.append(member.filename)
        if unsafe:
            raise CrawlerError(f"ZIP contem caminhos inseguros: {unsafe[:3]}")
        bad_member = archive.testzip()
        if bad_member:
            raise CrawlerError(f"CRC invalido no membro: {bad_member}")
        spreadsheets = [
            member for member in members
            if PurePosixPath(member.filename).suffix.lower() in allowed_spreadsheets
        ]

    if not members:
        raise CrawlerError(f"ZIP sem arquivos: {path}")
    if not spreadsheets:
        raise CrawlerError(f"ZIP sem planilhas reconhecidas: {path}")
    return {
        "archive_members": len(members),
        "spreadsheet_members": len(spreadsheets),
    }


class IbgeRegistryCrawler:
    def __init__(
        self,
        *,
        timeout: float = 60.0,
        retries: int = 3,
        backoff: float = 1.5,
        request_interval: float = 0.2,
    ) -> None:
        if timeout <= 0 or retries < 1 or backoff < 0 or request_interval < 0:
            raise ValueError("Parametros de rede invalidos")
        self.timeout = timeout
        self.retries = retries
        self.backoff = backoff
        self.request_interval = request_interval
        self._last_request = 0.0

    @staticmethod
    def _validate_official_url(url: str) -> None:
        parsed = urlparse(url)
        if parsed.scheme != "https" or parsed.hostname != "ftp.ibge.gov.br":
            raise CrawlerError(f"URL fora do host oficial permitido: {url}")
        if not parsed.path.startswith("/Registro_Civil/"):
            raise CrawlerError(f"URL fora da arvore Registro_Civil: {url}")

    def _wait_rate_limit(self) -> None:
        remaining = self.request_interval - (time.monotonic() - self._last_request)
        if remaining > 0:
            time.sleep(remaining)

    def _open(self, url: str):
        self._validate_official_url(url)
        last_error: Exception | None = None
        for attempt in range(1, self.retries + 1):
            try:
                self._wait_rate_limit()
                request = Request(url, headers={"User-Agent": USER_AGENT})
                response = urlopen(request, timeout=self.timeout)
                try:
                    self._validate_official_url(response.geturl())
                except Exception:
                    response.close()
                    raise
                self._last_request = time.monotonic()
                return response
            except HTTPError as exc:
                self._last_request = time.monotonic()
                if exc.code in {400, 401, 403, 404}:
                    raise CrawlerError(f"HTTP {exc.code} em {url}") from exc
                last_error = exc
            except (URLError, TimeoutError, OSError) as exc:
                self._last_request = time.monotonic()
                last_error = exc
            if attempt < self.retries:
                time.sleep(self.backoff * attempt)
        raise CrawlerError(
            f"Falha apos {self.retries} tentativa(s) em {url}: {last_error}"
        ) from last_error

    def get_html(self, url: str) -> str:
        with self._open(url) as response:
            body = response.read()
            charset = response.headers.get_content_charset() or "utf-8"
        try:
            return body.decode(charset)
        except (LookupError, UnicodeDecodeError):
            return body.decode("latin-1", errors="replace")

    def list_links(self, url: str) -> list[str]:
        return extract_links(self.get_html(url))

    def probe_public_catalog(self) -> dict[str, object]:
        raw_links = self.list_links(ROOT_URL)
        root_path = PurePosixPath(urlparse(ROOT_URL).path)
        entries: list[str] = []
        for href in raw_links:
            absolute = urljoin(ROOT_URL, href)
            parsed = urlparse(absolute)
            if parsed.hostname != "ftp.ibge.gov.br":
                continue
            path = PurePosixPath(parsed.path)
            if path == root_path or path.parent != root_path:
                continue
            entries.append(unquote(path.name) + ("/" if parsed.path.endswith("/") else ""))
        entries = sorted(set(entries))
        microdata_candidates = [
            entry for entry in entries if "microdado" in _fold_text(entry)
        ]
        return {
            "checked_at_utc": _utc_now(),
            "catalog_url": ROOT_URL,
            "advertised_root_entries": entries,
            "microdata_link_candidates": microdata_candidates,
            "public_microdata_link_discovered": bool(microdata_candidates),
            "result_tables_url": RESULTS_URL,
            "official_confidentiality_policy": CONFIDENTIALITY_URL,
            "restricted_access_service": SAR_URL,
            "interpretation": (
                "O catalogo raiz anuncia somente codigos e tabelas de resultados; "
                "a ausencia de link nao substitui a politica oficial, que informa que "
                "os microdados do Registro Civil nao tem divulgacao publica."
            ),
        }

    def discover(self, year: int, requested_format: str = "auto") -> Asset:
        year_url = urljoin(RESULTS_URL, f"{year}/")
        top_links = self.list_links(year_url)
        available_dirs: dict[str, str] = {}
        for href in top_links:
            absolute = urljoin(year_url, href)
            parsed = urlparse(absolute)
            name = PurePosixPath(parsed.path.rstrip("/")).name.lower()
            if parsed.path.endswith("/") and name in FORMAT_PREFERENCE:
                available_dirs[name] = absolute

        formats = FORMAT_PREFERENCE if requested_format == "auto" else (requested_format,)
        for file_format in formats:
            catalog_url = available_dirs.get(file_format)
            if not catalog_url:
                continue
            archive_href = select_marriage_archive(self.list_links(catalog_url))
            if not archive_href:
                continue
            source_url = urljoin(catalog_url, archive_href)
            self._validate_official_url(source_url)
            filename = unquote(PurePosixPath(urlparse(source_url).path).name)
            if filename != Path(filename).name:
                raise CrawlerError(f"Nome de arquivo inseguro: {filename}")
            return Asset(
                year=year,
                file_format=file_format,
                source_url=source_url,
                filename=filename,
                catalog_url=catalog_url,
            )
        raise CrawlerError(
            f"Nenhum arquivo 04casamentos encontrado para {year} "
            f"(formato={requested_format})"
        )

    def download(self, asset: Asset, output_dir: Path, force: bool = False) -> ManifestRow:
        year_dir = output_dir / str(asset.year)
        year_dir.mkdir(parents=True, exist_ok=True)
        destination = year_dir / asset.filename
        checkpoint = "downloaded"

        if destination.exists() and not force:
            validation = validate_archive(destination)
            checkpoint = "reused_valid_checkpoint"
        else:
            partial = destination.with_name(destination.name + ".part")
            expected_length: int | None = None
            written = 0
            try:
                with self._open(asset.source_url) as response, partial.open("wb") as target:
                    length_header = response.headers.get("Content-Length")
                    if length_header and length_header.isdigit():
                        expected_length = int(length_header)
                    while True:
                        chunk = response.read(1024 * 1024)
                        if not chunk:
                            break
                        target.write(chunk)
                        written += len(chunk)
                    target.flush()
                    os.fsync(target.fileno())
                if expected_length is not None and written != expected_length:
                    raise CrawlerError(
                        f"Download truncado: {written} de {expected_length} bytes"
                    )
                validation = validate_archive(partial)
                os.replace(partial, destination)
            except Exception:
                logging.exception("Falha ao baixar %s; parcial mantido em %s", asset.source_url, partial)
                raise

        return ManifestRow(
            year=asset.year,
            status="ok",
            data_level="public_aggregate_result_tables_not_microdata",
            file_format=asset.file_format,
            source_url=asset.source_url,
            local_path=str(destination.resolve()),
            size_bytes=destination.stat().st_size,
            sha256=sha256_file(destination),
            archive_members=validation["archive_members"],
            spreadsheet_members=validation["spreadsheet_members"],
            checkpoint=checkpoint,
            checked_at_utc=_utc_now(),
            note=(
                "Arquivo classificado pelo IBGE na arvore Tabelas_de_Resultados; "
                "deve ser tratado como planilha agregada, nao como microdados."
            ),
        )


def write_json_atomic(path: Path, payload: object) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    partial = path.with_name(path.name + ".part")
    with partial.open("w", encoding="utf-8") as target:
        json.dump(payload, target, ensure_ascii=False, indent=2, sort_keys=True)
        target.write("\n")
        target.flush()
        os.fsync(target.fileno())
    os.replace(partial, path)


def write_manifest_atomic(path: Path, rows: list[ManifestRow]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    partial = path.with_name(path.name + ".part")
    fieldnames = list(ManifestRow.__dataclass_fields__)
    with partial.open("w", encoding="utf-8", newline="") as target:
        writer = csv.DictWriter(target, fieldnames=fieldnames)
        writer.writeheader()
        writer.writerows(asdict(row) for row in rows)
        target.flush()
        os.fsync(target.fileno())
    os.replace(partial, path)


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        description=(
            "Descobre, baixa e audita as tabelas publicas de casamentos do "
            "Registro Civil no catalogo oficial do IBGE."
        )
    )
    parser.add_argument(
        "--years",
        default=f"{DEFAULT_YEARS[0]}:{DEFAULT_YEARS[-1]}",
        help="Ano, lista ou intervalo inclusivo (padrao: 2013:2024)",
    )
    parser.add_argument(
        "--format",
        choices=("auto",) + FORMAT_PREFERENCE,
        default="auto",
        help="auto prefere xlsx, depois xls e ods",
    )
    parser.add_argument("--output-dir", type=Path, default=DEFAULT_OUTPUT_DIR)
    parser.add_argument("--dry-run", action="store_true", help="Descobre URLs sem baixar ZIPs")
    parser.add_argument(
        "--probe-only",
        action="store_true",
        help="Audita apenas as entradas anunciadas no catalogo raiz",
    )
    parser.add_argument(
        "--force",
        action="store_true",
        help="Substitui atomicamente um checkpoint existente apos validar o novo ZIP",
    )
    parser.add_argument("--timeout", type=float, default=60.0)
    parser.add_argument("--retries", type=int, default=3)
    parser.add_argument("--backoff", type=float, default=1.5)
    parser.add_argument("--request-interval", type=float, default=0.2)
    parser.add_argument("--verbose", action="store_true")
    return parser


def main(argv: list[str] | None = None) -> int:
    args = build_parser().parse_args(argv)
    logging.basicConfig(
        level=logging.DEBUG if args.verbose else logging.INFO,
        format="%(asctime)s [%(levelname)s] %(message)s",
    )
    try:
        years = parse_years(args.years)
    except argparse.ArgumentTypeError as exc:
        raise SystemExit(str(exc)) from exc

    output_dir = args.output_dir.resolve()
    output_dir.mkdir(parents=True, exist_ok=True)
    crawler = IbgeRegistryCrawler(
        timeout=args.timeout,
        retries=args.retries,
        backoff=args.backoff,
        request_interval=args.request_interval,
    )

    try:
        probe = crawler.probe_public_catalog()
    except CrawlerError as exc:
        logging.error("Falha no probe do catalogo: %s", exc)
        return 1
    probe_path = output_dir / "catalog_probe.json"
    write_json_atomic(probe_path, probe)
    logging.info(
        "Catalogo: %d entrada(s), link publico de microdados=%s",
        len(probe["advertised_root_entries"]),
        probe["public_microdata_link_discovered"],
    )
    if args.probe_only:
        print(json.dumps(probe, ensure_ascii=False, indent=2, sort_keys=True))
        print(f"Probe salvo em {probe_path}")
        return 0

    rows: list[ManifestRow] = []
    errors = 0
    for index, year in enumerate(years, start=1):
        logging.info("[%d/%d] Descobrindo %d", index, len(years), year)
        try:
            asset = crawler.discover(year, args.format)
            if args.dry_run:
                rows.append(
                    ManifestRow(
                        year=year,
                        status="discovered",
                        data_level="public_aggregate_result_tables_not_microdata",
                        file_format=asset.file_format,
                        source_url=asset.source_url,
                        local_path="",
                        size_bytes=None,
                        sha256="",
                        archive_members=None,
                        spreadsheet_members=None,
                        checkpoint="not_downloaded_dry_run",
                        checked_at_utc=_utc_now(),
                        note="URL oficial descoberta; nenhum arquivo baixado.",
                    )
                )
                continue
            row = crawler.download(asset, output_dir, force=args.force)
            rows.append(row)
            logging.info(
                "  -> %s, %d bytes, %d planilha(s), checkpoint=%s",
                asset.filename,
                row.size_bytes,
                row.spreadsheet_members,
                row.checkpoint,
            )
        except (CrawlerError, OSError, zipfile.BadZipFile) as exc:
            errors += 1
            logging.error("  -> Falha em %d: %s", year, exc)
            rows.append(
                ManifestRow(
                    year=year,
                    status="error",
                    data_level="unknown",
                    file_format=args.format,
                    source_url="",
                    local_path="",
                    size_bytes=None,
                    sha256="",
                    archive_members=None,
                    spreadsheet_members=None,
                    checkpoint="none",
                    checked_at_utc=_utc_now(),
                    note=str(exc),
                )
            )

    manifest_path = output_dir / "manifest.csv"
    write_manifest_atomic(manifest_path, rows)
    ok = sum(row.status in {"ok", "discovered"} for row in rows)
    print(
        f"Concluido: {ok}/{len(rows)} ano(s) sem erro; "
        f"manifesto em {manifest_path}"
    )
    print(
        "Classificacao: tabelas publicas agregadas; microdados individuais "
        "continuam sujeitos ao acesso restrito do IBGE/SAR."
    )
    return 1 if errors else 0


if __name__ == "__main__":
    sys.exit(main())
