PYTHON=python3

RUNTEST=$(PYTHON) -m unittest -v -b
ALLMODULES=$(patsubst %.py, %.py, $(wildcard test*.py))

all: $(test) $(package)

package:
	$(PYTHON) setup.py bdist_wheel

clean:
	rm -f ./dist/*.whl

upload:
	$(PYTHON) -m twine upload --verbose --config-file .pypirc dist/*

test:
	${RUNTEST} ${ALLMODULES}

% : test%.py
	${RUNTEST} test$@

.PHONY: all package upload test

