OS := $(shell uname)
ifeq ($(OS), Darwin)
	# mainly for dev builds using homebrew things
    EXTRA_LDFLAGS ?= -L/usr/local/Cellar/openssl@1.1/1.1.1k/lib
    ARGP ?= /usr/local/Cellar/argp-standalone/1.3/lib/libargp.a
endif

CC ?= gcc
CFLAGS ?= -fpic -msse3 -O3 -std=c99
EXTRA_CFLAGS ?=
EXTRA_LDFLAGS ?=
EXTRA_LIBS ?=
HTS_CONF_ARGS ?=


.PHONY: default
default: modbam2bed


htslib/libhts.a:
	@echo Compiling $(@F)
	cd htslib/ \
		&& autoheader \
		&& autoconf \
		&& CFLAGS="$(CFLAGS) $(EXTRA_CFLAGS)" ./configure $(HTS_CONF_ARGS) \
		&& make -j 4


.PHONY: clean_htslib
clean_htslib:
	cd htslib && make clean || exit 0


obj/%.o: src/%.c
	mkdir -p obj && \
		$(CC) -c -pthread -Wall -fstack-protector-strong -D_FORTIFY_SOURCE=2 $(CFLAGS) \
		-Isrc -Ihtslib $(EXTRA_CFLAGS) $^ -o $@

.PHONY: clean_obj
clean_obj:
	rm -rf obj


modbam2bed: obj/modbam2bed.o obj/common.o obj/counts.o obj/bamiter.o obj/args.o htslib/libhts.a
	$(CC) -pthread -Wall -fstack-protector-strong -D_FORTIFY_SOURCE=2 $(CFLAGS) \
		-Isrc -Ihtslib $(EXTRA_CFLAGS) $(EXTRA_LDFLAGS)\
		$^ $(ARGP) \
		-lm -lz -llzma -lbz2 -lpthread -lcurl -lcrypto $(EXTRA_LIBS) \
		-o $(@)

.PHONY: clean
clean: clean_obj clean_htslib
	rm -rf modbam2bed

.PHONY: mem_check
mem_check: modbam2bed
	valgrind --error-exitcode=1 --tool=memcheck --leak-check=full --show-leak-kinds=all -s \
		./modbam2bed -b 0.66 -a 0.33 -t 2 -r ecoli1 test_data/400ecoli.bam test_data/ecoli.fasta.gz > /dev/null


### Python

PYTHON ?= python3
VENV ?= venv
venv: ${VENV}/bin/activate
IN_VENV=. ./${VENV}/bin/activate

$(VENV)/bin/activate:
	test -d $(VENV) || $(PYTHON) -m venv $(VENV) --prompt "modbam"
	${IN_VENV} && pip install pip --upgrade
	${IN_VENV} && pip install setuptools

.PHONY: python
python: htslib/libhts.a pymod.a $(VENV)/bin/activate
	${IN_VENV} && pip install -r requirements.txt
	${IN_VENV} && python setup.py develop

.PHONY: clean_python
clean_python: clean_obj
	rm -rf dist build modbampy.egg-info pymod.a libmodbampy.abi3.so ${VENV}

pymod.a: obj/common.o obj/bamiter.o obj/counts.o obj/args.o 
	ar rcs $@ $^
