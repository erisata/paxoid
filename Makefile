REBAR=rebar3


all: compile

compile:
	$(REBAR) compile

clean:
	$(REBAR) clean

test: eunit
itest: ct
check: test itest

eunit:
	$(REBAR) eunit

ct:
	$(REBAR) ct

.PHONY: all compile clean test itest check eunit ct

