SHELL := /bin/bash
all: *.deb *.rpm

build-deps:
	gem install fpm

clean:
	rm -f ruby-libvirt*.deb

test:
	ruby lib/libvirtskillz.rb 

*.rpm:
	fpm -v 0.2 -d ruby-nokogiri -d ruby-libvirt -s dir -t rpm -n ruby-libvirtskillz --prefix /usr/lib/ruby/site_ruby/ lib/libvirtskillz.rb

*.deb: clean test lib/libvirtskillz.rb
	fpm -v 0.3 -d ruby-nokogiri -d ruby-libvirt -s dir -t deb -n ruby-libvirtskillz --prefix /usr/lib/ruby/vendor_ruby/ lib/libvirtskillz.rb
