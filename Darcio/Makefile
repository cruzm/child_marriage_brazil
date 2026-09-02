.PHONY: all test reports

all:
	./Darcio/run_all.sh

test:
	Rscript Darcio/tests/run_tests.R

reports:
	Rscript Darcio/src/19_export_results.R
	Rscript Darcio/src/20_write_reports.R

