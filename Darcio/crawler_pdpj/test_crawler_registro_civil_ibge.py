import tempfile
import unittest
import zipfile
from pathlib import Path

from crawler_pdpj.crawler_registro_civil_ibge import (
    CrawlerError,
    IbgeRegistryCrawler,
    extract_links,
    parse_years,
    select_marriage_archive,
    sha256_file,
    validate_archive,
)


class RegistryCrawlerUnitTests(unittest.TestCase):
    def test_parse_years(self):
        self.assertEqual(parse_years("2013:2015"), [2013, 2014, 2015])
        self.assertEqual(parse_years("2024,2013,2024"), [2013, 2024])

    def test_parse_years_rejects_descending_interval(self):
        with self.assertRaises(Exception):
            parse_years("2024:2013")

    def test_extract_and_select_archive(self):
        html = """
        <a href="../">Parent</a>
        <a href="01nascidosvivos_xlsx.zip">Nascimentos</a>
        <a href="04casamentos_xlsx_20240101.zip">Casamentos antigo</a>
        <a href="04casamentos_xlsx_20250923.zip">Casamentos atual</a>
        """
        links = extract_links(html)
        self.assertEqual(
            select_marriage_archive(links),
            "04casamentos_xlsx_20250923.zip",
        )

    def test_official_url_guard(self):
        IbgeRegistryCrawler._validate_official_url(
            "https://ftp.ibge.gov.br/Registro_Civil/Tabelas_de_Resultados/2024/"
        )
        with self.assertRaises(CrawlerError):
            IbgeRegistryCrawler._validate_official_url(
                "https://example.org/Registro_Civil/arquivo.zip"
            )

    def test_validate_archive_and_hash(self):
        with tempfile.TemporaryDirectory() as directory:
            archive_path = Path(directory) / "04casamentos_xlsx.zip"
            with zipfile.ZipFile(archive_path, "w", zipfile.ZIP_DEFLATED) as archive:
                archive.writestr("Tabela 4.1.xlsx", b"conteudo-de-teste")
                archive.writestr("Tabela 4.2.xlsx", b"outro-conteudo")
            result = validate_archive(archive_path)
            self.assertEqual(result["archive_members"], 2)
            self.assertEqual(result["spreadsheet_members"], 2)
            self.assertRegex(sha256_file(archive_path), r"^[0-9a-f]{64}$")

    def test_validate_archive_rejects_traversal(self):
        with tempfile.TemporaryDirectory() as directory:
            archive_path = Path(directory) / "unsafe.zip"
            with zipfile.ZipFile(archive_path, "w") as archive:
                archive.writestr("../Tabela.xlsx", b"x")
            with self.assertRaises(CrawlerError):
                validate_archive(archive_path)


if __name__ == "__main__":
    unittest.main()
