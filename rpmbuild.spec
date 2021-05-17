Summary: Net::REST generic REST interfaces
Name: perl-Net-REST
Version: 2.0
Release: 0.%(perl -e '@t = gmtime(); printf ( "%04d%02d%02d%02d%02d%02d", $t[5] + 1900, $t[4] + 1, $t[3], $t[2], $t[1], $t[0] );')
License: NederHost
Vendor: NederHost
Source: %{name}
BuildArch: noarch
BuildRoot: %{_tmppath}/%{name}-buildroot

%define _unpackaged_files_terminate_build 0

%description
Net::REST interface module; contains a toolbox for accessing standard REST
interfaces as well as a number of specific module to support some APIs.

%prep
cd $RPM_BUILD_DIR
cp -r $RPM_SOURCE_DIR/$RPM_PACKAGE_NAME .
cd $RPM_PACKAGE_NAME
perl Makefile.PL

%build
cd $RPM_BUILD_DIR/$RPM_PACKAGE_NAME
make DESTDIR=$RPM_BUILD_ROOT

%install
cd $RPM_BUILD_DIR/$RPM_PACKAGE_NAME
make install DESTDIR=$RPM_BUILD_ROOT

%clean
rm -rf $RPM_BUILD_DIR/$RPM_PACKAGE_NAME

%files
/usr/local/share/perl5/Net/REST.pm
/usr/local/share/perl5/Net/REST
