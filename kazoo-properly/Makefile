CWD = $(shell pwd -P)
ROOT ?= $(realpath $(CWD)/../..)
PROJECT = properly

ERLC_OPTS = +'{lager_extra_sinks, [data]}'

MP3 = priv/mp3.mp3
LOGO = priv/logo.png

COMPILE_MOAR = assets

all: compile assets

assets: $(MP3) \
	 $(LOGO)

$(MP3):
	@mkdir -p $(shell dirname $(MP3))
	wget -qO $@ https://raw.githubusercontent.com/mathiasbynens/small/master/mp3.mp3

$(LOGO):
	@mkdir -p $(shell dirname $(LOGO))
	wget -qO $@ https://github.com/mathiasbynens/small/raw/master/png-transparent.png

python:
	@python3 -mpip install --user --upgrade opencv-python numpy Image pyzbar

clean: clean-pem-files

clean-pem-files:
	@rm -f priv/*.pem

include $(ROOT)/make/kz.mk
