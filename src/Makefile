EBIN_DIR=../ebin
INCLUDE_DIR=../include
ERLC=erlc
ERLC_FLAGS= -W -I $(INCLUDE_DIR) -o $(EBIN_DIR)
ERL=erl -noshell

$(EBIN_DIR)/%.beam: %.erl
	@mkdir -p $(EBIN_DIR)
	$(ERLC) $(ERLC_FLAGS) $<

$(EBIN_DIR)/%.app: %.app
	@mkdir -p $(EBIN_DIR)
	@cp $< $@


OBJECTS=misultin_socket \
		misultin_req \
		misultin

APP=misultin


all: ${OBJECTS:%=$(EBIN_DIR)/%.beam} ${APP:%=$(EBIN_DIR)/%.app}
	@echo All Done


clean:
	@rm -rf $(EBIN_DIR)
	@rm -f erl_crash.dump
