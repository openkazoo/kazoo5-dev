CWD = $(shell pwd -P)
ROOT ?= $(realpath $(CWD)/../..)
PROJECT = crossbar

TIMEZONE_JSON = $(CWD)/priv/couchdb/schemas/timezone.json

DEPS_LIST_TXT = $(CWD)/priv/deps_list.txt

COMPILE_MOAR = $(TIMEZONE_JSON)

CLEAN_MOAR = clean-port-request-scheduled-schema

all: compile $(DEPS_LIST_TXT)

eunit: cb-test

test: cb-test

cb-test:
	$(MAKE) compile-test -C $(ROOT)/core/kazoo_endpoint/

timezone:
	@ERL_LIBS=$(ROOT)/deps/:$(ROOT)/core/:$(ROOT)/applications/ $(CWD)/scripts/timezones.escript

$(TIMEZONE_JSON):
	@ERL_LIBS=$(ROOT)/deps/:$(ROOT)/core/:$(ROOT)/applications/ $(CWD)/scripts/timezones.escript

clean-port-request-scheduled-schema:
	$(if $(wildcard $(COMPILE_MOAR)), rm -f $(COMPILE_MOAR))

deps_list:
	@$(CWD)/scripts/list_deps.escript $(DEPS_LIST_TXT) $(ROOT)/deps

$(DEPS_LIST_TXT):
	@$(CWD)/scripts/list_deps.escript $(DEPS_LIST_TXT) $(ROOT)/deps

include $(ROOT)/make/kz.mk
