=head1 NAME

Finance::Bank::NetBranch - Manage your NetBranch accounts with Perl

=head1 SYNOPSIS

  use Finance::Bank::NetBranch;
  my $nb = Finance::Bank::NetBranch->new(
      url      => 'https://nbp1.cunetbranch.com/valley/',
      account  => '12345',
      password => 'abcdef',
  );

  my @accounts = $nb->accounts;

  foreach (@accounts) {
      printf "%20s : %8s : USD %9.2f of %9.2f\n",
          $_->name, $_->account_no, $_->available, $_->balance;
  }

=head1 DESCRIPTION

This module provides a rudimentary interface to NetBranch online banking. This
module was originally implemented to interface with Valley Communities Credit
Union's page at C<https://nbp1.cunetbranch.com/valley/>, but the behavior of
the module is theoretically generalized to "NetBranch" type online access.
However, I do not have access to another NetBranch account with another bank,
and so any feedback on the actual behavior of this module would be greatly
appreciated.

You will need either C<Crypt::SSLeay> or C<IO::Socket::SSL> installed 
for HTTPS support to work. C<Alias>, C<HTML::Entities>, and C<WWW::Mechanize>
are required.

=cut
package Finance::Bank::NetBranch;

use strict;
use warnings;

use Alias 'attr';
use HTML::Entities;
use WWW::Mechanize;
$Alias::AttrPrefix = "main::";	# make use strict 'vars' palatable

our $VERSION = 0.01;

=head1 CLASS METHODS

=over 4

=item new

Creates a new Finance::Bank::NetBranch object; does not connect to the server.

=cut
sub new {
	my $type = shift;
	my $self = bless { @_ }, $type;
	$self;
}

=item accounts

Retrieves cached accounts information, connecting to the server if necessary.

=cut
sub accounts { my $self = shift; @{ $self->{accounts} || $self->refresh } }

=item refresh

Refreshes cached account information, returning the same data as accounts().

=cut
sub refresh {
	my $self = attr shift;
	my $m = WWW::Mechanize->new;

	$m->get($::url)
		or die "Could not fetch login page URL '$::url'";

	my $result = $m->submit_form(
		form_name => 'frmLogin',
		fields	=> {
			USERNAME	=> $::account,
			PASSWORD	=> $::password,
		},
		button    => 'Login'
	) or die "Could not submit login form as account '$::account'";

	my ($user, undef, $private) = $result->content =~ m!
		<h3>welcome\s*([^<]+)</h3>member\s*\#(\d+)\s*\(<b>([^<]+)</b>\)<br>
	!imox;
	$user = decode_entities($user);

	my @a;
	my @accounts = map {
		my ($name, $account_no, $bal, $avail) = @$_;
		$avail =~ s/,//; $bal =~ s/,//;
		bless {
			available	=> $avail,
			balance		=> $bal,
			account_no	=> $account_no,
			name		=> $name,
			sort_code	=> $name,
		}, "Finance::Bank::NetBranch::Account";
	} map {	# Return values three at a time in an arrayref
		(push @a, $_) > 3 ? [ splice(@a, 0) ] : ()
	} ($result->content =~ m!
		<tr>\s*
			<td[^>]*?>\s*
				<span[^>]*?>\s*
					<a[^>]*?>\s*([^\(<]+?\s+\(([^\)]+)\))\s*</a>\s*
				</span>\s*
			</td>\s*
			<td[^>]*?>\s*
			# I don't actually know where the negative sign would be, happily
				<span[^>]*?>\s*(?:-?\$([-\d,.]+))\s*</span>\s*
			</td>\s*
			<td[^>]*?>\s*
				<span[^>]*?>\s*(?:-?\$([-\d,.]+))\s*</span>\s*
			</td>\s*
		</tr>\s*
	!igmox);

	$m->follow_link(text_regex => qr/Logout/)
		or die "Failed to log out";
	
	$self->{accounts} = \@accounts;
}

=back

=head1 OBJECT METHODS

  $ac->name
  $ac->sort_code
  $ac->account_no

Return the account name, sort code and the account number. The sort code is
just the name in this case, but it has been included for consistency with 
other Finance::Bank::* modules.

  $ac->balance
  $ac->available

Return the account balance or available amount as a signed floating point value.

=cut
package Finance::Bank::NetBranch::Account;
# Basic OO smoke-and-mirrors Thingy (from Finance::Card::Citibank)
no strict;
sub AUTOLOAD { my $self = shift; $AUTOLOAD =~ s/.*:://; $self->{$AUTOLOAD} }

1;

__END__

=head1 WARNING

This warning is verbatim from Simon Cozens' C<Finance::Bank::LloydsTSB>,
and certainly applies to this module as well.

This is code for B<online banking>, and that means B<your money>, and
that means B<BE CAREFUL>. You are encouraged, nay, expected, to audit
the source of this module yourself to reassure yourself that I am not
doing anything untoward with your banking data. This software is useful
to me, but is provided under B<NO GUARANTEE>, explicit or implied.

=head1 BUGS

Probably, but moreso lack of such incredibly dangerous features as transfers, scheduled transfers, etc., coming in a future release. Maybe.

Please report any bugs or feature requests to
C<bug-finance-bank-netbranch at rt.cpan.org>, or through the web interface at
L<http://rt.cpan.org/NoAuth/ReportBug.html?Queue=Finance-Bank-NetBranch>.
I will be notified, and then you'll automatically be notified of progress on
your bug as I make changes.

=head1 SUPPORT

You can find documentation for this module with the perldoc command.

    perldoc Finance::Bank::NetBranch

You can also look for information at:

=over 4

=item * AnnoCPAN: Annotated CPAN documentation

L<http://annocpan.org/dist/Finance-Bank-NetBranch>

=item * CPAN Ratings

L<http://cpanratings.perl.org/d/Finance-Bank-NetBranch>

=item * RT: CPAN's request tracker

L<http://rt.cpan.org/NoAuth/Bugs.html?Dist=Finance-Bank-NetBranch>

=item * Search CPAN

L<http://search.cpan.org/dist/Finance-Bank-NetBranch>

=back


=head1 THANKS

Mark V. Grimes for C<Finance::Card::Citibank>. The pod was taken from Mark's
module.

=head1 AUTHOR

Darren M. Kulp C<< <darren@kulp.ch> >>

=head1 COPYRIGHT AND LICENSE

Copyright (C) 2006 by Darren Kulp

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself, either Perl version 5.8.7 or,
at your option, any later version of Perl 5 you may have available.

=cut

