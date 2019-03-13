REBAR=rebar3


all: compile

compile:
	$(REBAR) compile

.PHONY: all compile

