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
      my $days = 20;
      for ($_->transactions(from => time - (86400 * $days), to => time)) {
          printf "%10s | %20s | %80s : %9.2f, %9.2f\n",
              $_->date->ymd, $_->type, $_->description, $_->amount, $_->balance;
      }
  }

=head1 DESCRIPTION

This module provides a rudimentary interface to NetBranch online banking. This
module was originally implemented to interface with Valley Communities Credit
Union's page at C<https://nbp1.cunetbranch.com/valley/>, but the behavior of
the module is theoretically generalized to "NetBranch" type online access.
However, I do not have access to another NetBranch account with another bank,
and so any feedback on the actual behavior of this module would be greatly
appreciated.

You will need either C<Crypt::SSLeay> or C<IO::Socket::SSL> installed for HTTPS
support to work.

=cut
package Finance::Bank::NetBranch;

use strict;
use warnings;

use Alias 'attr';
use Carp;
use Date::Parse;
use DateTime;
use HTML::Entities;
use WWW::Mechanize;
$Alias::AttrPrefix = "main::";	# make use strict 'vars' palatable

our $VERSION = 0.03;

=head1 CLASS METHODS

=head2 Finance::Bank::NetBranch

=over 4

=item new

Creates a new C<Finance::Bank::NetBranch> object; does not connect to the server.

=cut
sub new {
	my $type = shift;
	bless {	@_ }, $type;
}

=back

=head1 OBJECT METHODS

=head2 Finance::Bank::NetBranch

=over 4

=item accounts

Retrieves cached accounts information, connecting to the server if necessary.

=cut
sub accounts { my $self = attr shift; @::accounts || @{ $self->_get_balances } }

=item _login

Logs into the NetBranch site (internal use only)

=cut
sub _login {
	my $self = attr shift;

	$::mech ||= WWW::Mechanize->new;
	$::mech->get($::url)
		or die "Could not fetch login page URL '$::url'";
	my $result = $::mech->submit_form(
		form_name => 'frmLogin',
		fields	=> {
			USERNAME	=> $::account,
			PASSWORD	=> $::password,
		},
		button    => 'Login'
	) or die "Could not submit login form as account '$::account'";

	$::mech->uri =~ /welcome/i
		or die "Failed to log in as account '$::account'";

	$::logged_in = 1;
	$result;
}

=item _logout

Logs out of the NetBranch site (internal use only)

=cut
sub _logout {
	my $self = attr shift;
	$::mech->follow_link(text_regex => qr/Logout/)
		or die "Failed to log out";
	$::logged_in = 0;
}

=item _get_balances

Gets account balance information (internal use only)

=cut
sub _get_balances {
	my $self = attr shift;

	my $result = $self->_login unless $::logged_in;

	my ($user, undef, $private) = $result->content =~ m!
		<h3>welcome\s*([^<]+)</h3>member\s*\#(\d+)\s*\(<b>([^<]+)</b>\)<br>
	!imox;
	$user = decode_entities($user);

	my @a;
	my @accounts = map {
		my ($name, $account_no, $bal, $avail) = @$_;
		$avail =~ s/,//g; $bal =~ s/,//g; # Get rid of thousands separators
		bless {
			account_no	=> $account_no,
			# Detect trailing parenthesis (negative number)
			available	=> ($avail	=~ /([\d+.]+)\)/) ? -$1 : $avail,
			balance		=> ($bal	=~ /([\d+.]+)\)/) ? -$1 : $bal,
			name		=> $name,
			parent		=> $self,
			sort_code	=> $name,
			transactions	=> [],
		}, "Finance::Bank::NetBranch::Account";
	} map {	# Return values four at a time in an arrayref
		(push @a, $_) > 3 ? [ splice(@a, 0) ] : ()
	} ($result->content =~ m!
		<tr>\s*
			<td[^>]*?>\s*
				<span[^>]*?>\s*
					<a[^>]*?>\s*([^\(<]+?\s+\(([^\)]+)\))\s*</a>\s*
				</span>\s*
			</td>\s*
			<td[^>]*?>\s*
				<span[^>]*?>\s* \(? \$ ([\d,.]+ \)? )\s*</span>\s*
			</td>\s*
			<td[^>]*?>\s*
				<span[^>]*?>\s* \(? \$ ([\d,.]+ \)? )\s*</span>\s*
			</td>\s*
		</tr>\s*
	!igmox);
	
	$self->_logout;

	$self->{accounts} = \@accounts;
}

=item _get_transactions

Gets transaction information, given start and end dates (internal use only)

=cut
sub _get_transactions {
	my $self = attr shift;
	my ($account, %args) = @_;

	$self->_login unless $::logged_in;
	$::mech->follow_link(text_regex => qr/Account History/)
		or die "Failed to open account history mech";

	my $page = $::mech->follow_link(
		text_regex => qr/\($account->{account_no}\)/
	) or die "Failed to open history for account '$account->{account_no}'";

	# Convert dates into DateTime objects if necessary
	my ($from, $to) = map {
		ref($_) eq 'DateTime'
			? $_
			: DateTime->from_epoch(epoch => $_)
	} @args{qw(from to)};

	sub pad0 { sprintf "%0.2d", shift }

	$::mech->form_name('HistReq');

	$::mech->select('FM', pad0($from->month));
	$::mech->select('FD', $from->day);
	$::mech->select('FY', $from->year);

	$::mech->select('TM', pad0($to->month));
	$::mech->select('TD', $to->day);
	$::mech->select('TY', $to->year);

	$page = $::mech->submit
		or die "Could not submit history request form";

	my @a;
	# Reverse to put oldest transactions first
	my @transactions = reverse map {
		my ($date, $type, $desc, $amount, $bal) = @$_;
		$date = DateTime->from_epoch(epoch => str2time($date));
		$amount =~ s/,//g; $bal =~ s/,//g; # Get rid of thousands separators
		bless {
			# Detect trailing parenthesis (negative number)
			amount		=> ($amount	=~ /([\d+.]+)\)/) ? -$1 : $amount,
			balance		=> ($bal	=~ /([\d+.]+)\)/) ? -$1 : $bal,
			date		=> $date,
			description	=> decode_entities($desc),
			parent		=> $account,
			type		=> $type,
		}, "Finance::Bank::NetBranch::Transaction";
	} map {	# Return values five at a time in an arrayref
		(push @a, $_) > 4 ? [ splice(@a, 0) ] : ()
	} ($page->content =~ m!
		<tr>\s*
			(?:</span>\s*</td>)?\s*	# Incorrect markup
			<td[^>]*?>\s*
				# Date (m/d/yyyy)
				<span[^>]*?>\s*([\d/]+?)\s*</span>\s*
			</td>\s*
			<td[^>]*?>\s*
				# Type
				<span[^>]*?>\s*([^<]+?)\s*</span>\s*
			</td>\s*
			<td[^>]*?>\s*
				# Description
				<span[^>]*?>\s*([^<]+?)\s*</span>\s*
			</td>\s*
			<td[^>]*?>\s*
				# Amount
				<span[^>]*?>\s* \(? \$([\d,.]+ \)? )(?:&nbsp;|\s)*</span>\s*
			</td>\s*
			<td[^>]*?>\s*
				# New Balance (tm)
				<span[^>]*?>\s* \(? \$([\d,.]+ \)? )(?:&nbsp;|\s)*</span>\s*
			</td>\s*
		</tr>\s*
	!igmox);

	$self->_logout;
	@transactions;
}

=back

=head2 Finance::Bank::NetBranch::Account

=over 4

=item name

=item sort_code

=item account_no

Return the account name, sort code or account number. The sort code is just the
name in this case, but it has been included for consistency with other
Finance::Bank::* modules.

=item balance

=item available

Return the account balance or available amount as a signed floating point value.

=item transactions(from => $start_date, to => $end_date)

Retrieves C<Finance::Bank::NetBranch::Transaction> objects for the specified
account object between two dates (unix timestamps or DateTime objects).

=back

=cut
package Finance::Bank::NetBranch::Account;
# Basic OO smoke-and-mirrors Thingy (from Finance::Card::Citibank)
use Alias 'attr';
use Carp;

no strict;
sub AUTOLOAD { my $self = shift; $AUTOLOAD =~ s/.*:://; $self->{$AUTOLOAD} }

sub transactions ($%) {
	my $self = attr shift;
	my (%args) = @_;
	$args{from} && $args{to}
		or croak "Must supply from and to dates";
	@::transactions =
		(@::transactions || $::parent->_get_transactions($self, %args));
}

=head2 Finance::Bank::NetBranch::Transaction

=over 4

=item date

=item type

=item description

=item amount

=item balance

Return appropriate data from this transaction.

=back

=cut
package Finance::Bank::NetBranch::Transaction;
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

Probably, but moreso lack of such incredibly dangerous features as transfers,
scheduled transfers, etc., coming in a future release. Maybe.

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

