# Copyright (c) 2003 Mikhael Goikhman
#
# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation; either version 2 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program; if not, write to the Free Software
# Foundation, Inc., 59 Temple Place, Suite 330, Boston, MA  02111-1307  USA

package FVWM::Module::Toolkit;

use 5.004;
use strict;
use vars qw($VERSION @ISA $_dialogTool);

use FVWM::Module;

BEGIN {
	$VERSION = $FVWM::Module::VERSION;
	@ISA = qw(FVWM::Module);
}

sub import ($@) {
	my $class = shift;
	my $caller = caller;
	my $error = 0;
	my $name = "*undefined*";

	while (@_) {
		$name = shift;
		if ($name eq 'base') {
			next if UNIVERSAL::isa($caller, __PACKAGE__);
			my $caller2 = (caller(1))[0];
			eval "
				package $caller2;
				use FVWM::Constants;

				package $caller;
				use vars qw(\$VERSION \@ISA);
				use FVWM::Constants;
				\$VERSION = \$FVWM::Module::Toolkit::VERSION;
				\@ISA = qw(FVWM::Module::Toolkit);
			";
			if ($@) {
				die "Internal error:\n$@";
			}
		} else {
			my ($name0, $args) = split(/>?=/, $name, 2);
			my $mod = $args? "$name0 split(/,/, q{$args})": $name;
			eval "
				package $caller;
				use $mod;
			";
			if ($@) {
				$error = 1;
				last;
			}
		}
	}
	if ($error) {
		my $scriptName = $0; $scriptName =~ s|.*/||;
		my $errorTitle = 'FVWM Perl library error';
		my $errorMsg = "$scriptName requires Perl package $name to be installed.\n\n";
		$errorMsg .= "You may either find it as a binary package for your distribution\n";
		$errorMsg .= "or download it from CPAN, http://cpan.org/modules/by-module/ .\n";
		$class->showMessage($errorMsg, $errorTitle, 1);
		print STDERR "[$errorTitle]: $errorMsg\n$@";
		exit(1);
	}
}

sub showError ($$;$) {
	my $self = shift;
	my $msg = shift;
	my $title = shift || ($self->name . " Error");

	$self->showMessage($msg, $title, 1);
	print STDERR "[$title]: $msg\n";
}

sub showMessage ($$;$) {
	my $self = shift;
	my $msg = shift;
	my $title = shift || ($self->name . " Message");
	my $noStderr = shift || 0;  # for private usage only

	unless ($_dialogTool) {
		my @dirs = split(':', $ENV{PATH});
		# kdialog is last because at least v0.9 ignores --title
		TOOL_CANDIDATE:
		foreach (qw(gdialog Xdialog gtk-shell xmessage kdialog)) {
			foreach my $dir (@dirs) {
				my $file = "$dir/$_";
				if (-x $file) {
					$_dialogTool = $_;
					last TOOL_CANDIDATE;
				}
			}
		}
	}
	my $tool = $_dialogTool || "xterm";

	$msg =~ s/'/'"'"'/sg;
	$title =~ s/'/'"'"'/sg;
	if ($tool eq "gdialog" || $tool eq "Xdialog" || $tool eq "kdialog") {
		system("$tool --title '$title' --msgbox '$msg' 500 100 &");
	} elsif ($tool eq "gtk-shell") {
		system("gtk-shell --size 500 100 --title '$title' --label '$msg' --button Close &");
	} elsif ($tool eq "xmessage") {
		system("xmessage -name '$title' '$msg' &");
	} else {
		$msg =~ s/"/\\"/sg;
		$msg =~ s/\n/\\n/sg;
		system("xterm -g 70x10 -T '$title' -e \"echo '$msg'; sleep 600000\" &");
	}
	print STDERR "[$title]: $msg\n" if $! && !$noStderr;
}

sub showDebug ($$;$) {
	my $self = shift;
	my $msg = shift;
	my $title = shift || ($self->name . " Debug");

	print STDERR "[$title]: $msg\n";
}

sub addDefaultErrorHandler ($) {
	my $self = shift;

	$self->addHandler(M_ERROR, sub {
		my ($self, $event) = @_;
		$self->showError($event->_text, "FVWM Error");
	});
}

1;

__END__

=head1 NAME

FVWM::Module::Toolkit - FVWM::Module with abstract widget toolkit attached

=head1 SYNOPSIS

1) May be used anywhere to require external Perl classes and report error in
the nice dialog if absent:

    use FVWM::Module::Toolkit qw(Tk X11::Protocol Tk::Balloon);

    use FVWM::Module::Toolkit qw(Tk=804.024,catch X11::Protocol>=0.52);

There is the same syntactic sugar as in "perl -M", with an addition
of ">=" being fully equivalent to "=". The ">=" form may look better for
the user in the error message. If the required Perl class is absent,
FVWM::Module::Toolkit->showMessage() is used to show the dialog and the
application dies.

2) This class should be uses to implement concrete toolkit subclasses.
A new toolkit subclass implementation may look like this:

    package FVWM::Module::SomeToolkit;
    # this automatically sets the base class and tries "use SomeToolkit;"
    use FVWM::Module::Toolkit qw(base SomeToolkit);

    sub showError ($$;$) {
        my ($self, $error, $title) = @_;
        $title ||= $self->name . " Error";

        # create a dialog box using SomeToolkit widgets
        SomeToolkit->Dialog(
            -title => $title,
            -text => $error,
            -buttons => ['Close'],
        );
    }

    sub eventLoop ($$) {
        my $self = shift;
        my @params = @_;

        # enter the SomeToolkit event loop with hooking $self->{istream}
        $self->eventLoopPrepared(@params);
        fileevent($self->{istream},
            read => sub {
                unless ($self->processPacket($self->readPacket)) {
                    $self->disconnect;
                    $top->destroy;
                }
                $self->eventLoopPrepared(@params);
            }
        );
        SomeToolkit->MainLoop;
        $self->eventLoopFinished(@params);
    }

=head1 DESCRIPTION

The B<FVWM::Module::Toolkit> package is a sub-class of B<FVWM::Module> that
is intended to be uses as the base of sub-classes that attach widget
toolkit library, like Perl/Tk or Gtk-Perl. It does some common work to load
widget toolkit libraries and to show an error in the external window like
xmessage if the required libraries are not available.

This class overloads one method B<addDefaultErrorHandler> and expects
sub-classes to overload the methods B<showError>, B<showMessage> and
B<showDebug> to use native widgets. These 3 methods are implemented in this
class, they extend the superclass versions by adding a title parameter and
using an external dialog tool to show error/message.

This manual page details only those differences. For details on the
API itself, see L<FVWM::Module>.

=head1 METHODS

Only overloaded or new methods are covered here:

=over 8

=item B<showError> I<msg> [I<title>]

This method is intended to be overridden in subclasses to create a dialog box
using the corresponding widgets. The default fall back implementation is
similar to B<showMessage>, but the error message (with title) is also always
printed to STDERR.

May be good for module diagnostics or any other purpose.

=item B<showMessage> I<msg> [I<title>]

This method is intended to be overridden in subclasses to create a dialog
box using the corresponding widgets. The default fall back implementation is
to find a system message application to show the message. The potentially
used applications are I<gdialog>, I<Xdialog>, I<gtk-shell>, I<xmessage>,
I<kdialog>, or I<xterm> as the last resort. If not given, I<title> is based
on the module name.

May be good for module debugging or any other purpose.

=item B<showDebug> I<msg> [I<title>]

This method is intended to be overridden in subclasses to create a dialog box
using the corresponding widgets. The default fall back implementation is
to print a message (with a title that is the module name by default)
to STDERR.

May be good for module debugging or any other purpose.

=item B<addDefaultErrorHandler>

This methods adds a M_ERROR handler to automatically notify you that an error
has been reported by FVWM. The M_ERROR handler then calls C<showError()>
with the received error text as a parameter to show it in a window.

=back

=head1 AUTHOR

Mikhael Goikhman <migo@homemail.com>.

=head1 SEE ALSO

For more information, see L<fvwm>, L<FVWM::Module>, L<FVWM::Module::Gtk>,
L<FVWM::Module::Gtk2>, L<FVWM::Module::Tk>.

=cut
