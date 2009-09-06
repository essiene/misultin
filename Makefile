NAME=misultin
VERSION=0.2.1
ERL_LIB=/usr/lib/erlang/lib
EBIN_DIR=ebin
INCLUDE_DIR=include
SRC_DIR=src
EXAMPLES_DIR=examples

#support debug compiles 
all: 
	@cd src;make
	@echo All Done

clean:
	@cd src;make clean
	@rm -rf ebin
	@rm -f erl_crash.dump
	@rm -f *.tar.gz
	@rm -rf $(NAME)-$(VERSION)

install: all
	@mkdir -p $(DESTDIR)/$(ERL_LIB)/$(NAME)-$(VERSION)/{ebin,include,src,examples}
	@cp $(EBIN_DIR)/* $(DESTDIR)/$(ERL_LIB)/$(NAME)-$(VERSION)/ebin/
	@cp $(INCLUDE_DIR)/* $(DESTDIR)/$(ERL_LIB)/$(NAME)-$(VERSION)/include/
	@cp $(SRC_DIR)/* $(DESTDIR)/$(ERL_LIB)/$(NAME)-$(VERSION)/src/
	@cp $(EXAMPLES_DIR)/* $(DESTDIR)/$(ERL_LIB)/$(NAME)-$(VERSION)/examples/

dist: clean
	@mkdir -p $(NAME)-$(VERSION)
	@cp README.txt LICENSE.txt Makefile $(NAME)-$(VERSION)
	@cp -r include src examples $(NAME)-$(VERSION)
	@tar -czvf $(NAME)-$(VERSION).tar.gz $(NAME)-$(VERSION)
	@rm -rf $(NAME)-$(VERSION)
