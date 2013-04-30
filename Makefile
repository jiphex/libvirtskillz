SHELL := /bin/bash
all: *.deb

build-deps:
	gem install fpm

clean:
	rm -f ruby-libvirt*.deb

test:
	ruby libvirtskillz.rb 

*.deb: clean test libvirtskillz.rb
	fpm -v 0.1 -d ruby-builder -d ruby-nokogiri -d ruby-libvirt -s dir -t deb -n ruby-libvirt-skillz --prefix /usr/lib/ruby/vendor_ruby/ libvirtskillz.rb
