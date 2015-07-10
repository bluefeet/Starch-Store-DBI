package Web::Starch::Store::DBI;

=head1 NAME

Web::Starch::Store::DBI - Session storage backend using DBI.

=head1 SYNOPSIS

    my $starch = Web::Starch->new(
        store => {
            class => '::DBI',
            dbh => [
                $dsn,
                $username,
                $password,
                { RaiseError => 1 },
            ],
            table => 'my_sessions',
        },
    );

=head1 DESCRIPTION

This Starch store uses L<DBI> to set and get session data.

Consider using L<Web::Starch::Store::DBIxConnector> instead
of this store as L<DBIx::Connector> provides superior re-connection
and transaction handling capabilities.

=cut

use DBI;
use Types::Standard -types;
use Types::Common::String -types;
use Scalar::Util qw( blessed );
use Data::Serializer::Raw;

use Moo;
use strictures 2;
use namespace::clean;

with qw(
    Web::Starch::Store
);

=head1 REQUIRED ARGUMENTS

=head2 dbh

This must be set to either array ref arguments for L<DBI/connect>
or a pre-built object (often retrieved using a method proxy).

When configuring Starch from static configuration files using a
L<method proxy|Web::Starch::Manual/METHOD PROXIES>
is a good way to link your existing L<DBI> object constructor
in with Starch so that starch doesn't build its own.

=cut

has _dbh_arg => (
    is       => 'ro',
    isa      => InstanceOf[ 'DBI::db' ] | ArrayRef,
    init_arg => 'dbh',
    required => 1,
);

has dbh => (
    is       => 'lazy',
    isa      => InstanceOf[ 'DBI::db' ],
    init_arg => undef,
);
sub _build_dbh {
    my ($self) = @_;

    my $dbh = $self->_dbh_arg();
    return $dbh if blessed $dbh;

    return DBI->connect( @$dbh );
}

=head1 OPTIONAL ARGUMENTS

=head2 serializer

A L<Data::Serializer::Raw> for serializing the session data for storage
in the L</data_column>.  Can be specified as string containing the
serializer name, a hashref of Data::Serializer::Raw arguments, or as a
pre-created Data::Serializer::Raw object.  Defaults to C<JSON>.

Consider using the C<JSON::XS> or C<Sereal> serializers for speed.

C<Sereal> will likely be the fastest and produce the most compact data.

=cut

has _serializer_arg => (
    is       => 'ro',
    isa      => InstanceOf[ 'Data::Serializer::Raw' ] | HashRef | NonEmptySimpleStr,
    init_arg => 'serializer',
    default  => 'JSON',
);

has serializer => (
    is       => 'lazy',
    isa      => InstanceOf[ 'Data::Serializer::Raw' ],
    init_arg => undef,
);
sub _build_serializer {
    my ($self) = @_;

    my $serializer = $self->_serializer_arg();
    return $serializer if blessed $serializer;

    if (ref $serializer) {
        return Data::Serializer::Raw->new( %$serializer );
    }

    return Data::Serializer::Raw->new(
        serializer => $serializer,
    );
}

=head2 table

The table name where sessions are stored in the database.
Defaults to C<sessions>.

=cut

has table => (
    is      => 'ro',
    isa     => NonEmptySimpleStr,
    default => 'sessions',
);

=head2 key_column

The column in the L</table> where the session ID is stored.

=cut

has key_column => (
    is      => 'ro',
    isa     => NonEmptySimpleStr,
    default => 'key',
);

=head2 data_column

The column in the L</table> which wil hold the session
data.  Defaults to C<data>.

=cut

has data_column => (
    is      => 'ro',
    isa     => NonEmptySimpleStr,
    default => 'data',
);

=head2 expiration_column

The column in the L</table> which will hold the epoch time
when the session should be expired.  Defaults to C<expiration>.

=cut

has expiration_column => (
    is      => 'ro',
    isa     => NonEmptySimpleStr,
    default => 'expiration',
);

=head1 ATTRIBUTES

=head2 insert_sql

The SQL used to create session data.

=cut

has insert_sql => (
    is       => 'lazy',
    isa      => NonEmptyStr,
    init_arg => undef,
);
sub _build_insert_sql {
    my ($self) = @_;

    return sprintf(
        'INSERT INTO %s (%s, %s, %s) VALUES (?, ?, ?)',
        $self->table(),
        $self->key_column(),
        $self->data_column(),
        $self->expiration_column(),
    );
}

=head2 update_sql

The SQL used to update session data.

=cut

has update_sql => (
    is       => 'lazy',
    isa      => NonEmptyStr,
    init_arg => undef,
);
sub _build_update_sql {
    my ($self) = @_;

    return sprintf(
        'UPDATE %s SET %s=?, %s=? WHERE %s=?',
        $self->table(),
        $self->data_column(),
        $self->expiration_column(),
        $self->key_column(),
    );
}

=head2 exists_sql

The SQL used to confirm whether session data already exists.

=cut

has exists_sql => (
    is       => 'lazy',
    isa      => NonEmptyStr,
    init_arg => undef,
);
sub _build_exists_sql {
    my ($self) = @_;

    return sprintf(
        'SELECT 1 FROM %s WHERE %s = ? AND %s > ?',
        $self->table(),
        $self->key_column(),
        $self->expiration_column(),
    );
}

=head2 select_sql

The SQL used to retrieve session data.

=cut

has select_sql => (
    is       => 'lazy',
    isa      => NonEmptyStr,
    init_arg => undef,
);
sub _build_select_sql {
    my ($self) = @_;

    return sprintf(
        'SELECT %s FROM %s WHERE %s = ? AND %s > ?',
        $self->data_column(),
        $self->table(),
        $self->key_column(),
        $self->expiration_column(),
    );
}

=head2 delete_sql

The SQL used to delete session data.

=cut

has delete_sql => (
    is       => 'lazy',
    isa      => NonEmptyStr,
    init_arg => undef,
);
sub _build_delete_sql {
    my ($self) = @_;

    return sprintf(
        'DELETE FROM %s WHERE %s = ?',
        $self->table(),
        $self->key_column(),
    );
}

=head1 METHODS

=head2 set

Set L<Web::Starch::Store/set>.

=head2 get

Set L<Web::Starch::Store/get>.

=head2 remove

Set L<Web::Starch::Store/remove>.

=cut

sub set {
    my ($self, $key, $data, $expires) = @_;

    my $dbh = $self->dbh();

    my $sth = $dbh->prepare_cached(
        $self->exists_sql(),
    );

    my ($exists) = $dbh->selectrow_array( $sth, undef, $key, time() );

    $data = $self->serializer->serialize( $data );
    $expires += time();

    if ($exists) {
        my $sth = $self->dbh->prepare_cached(
            $self->update_sql(),
        );

        $sth->execute( $data, $expires, $key );
    }
    else {
        my $sth = $self->dbh->prepare_cached(
            $self->insert_sql(),
        );

        $sth->execute( $key, $data, $expires );
    }

    return;
}

sub get {
    my ($self, $key) = @_;

    my $dbh = $self->dbh();

    my $sth = $dbh->prepare_cached(
        $self->select_sql(),
    );

    my ($data) = $dbh->selectrow_array( $sth, undef, $key, time() );

    return undef if !defined $data;

    return $self->serializer->deserialize( $data );
}

sub remove {
    my ($self, $key) = @_;

    my $dbh = $self->dbh();

    my $sth = $dbh->prepare_cached(
        $self->delete_sql(),
    );

    $sth->execute( $key );

    return;
}

1;
__END__

=head1 AUTHOR

Aran Clary Deltac <bluefeetE<64>gmail.com>

=head1 ACKNOWLEDGEMENTS

Thanks to L<ZipRecruiter|https://www.ziprecruiter.com/>
for encouraging their employees to contribute back to the open
source ecosystem.  Without their dedication to quality software
development this distribution would not exist.

=head1 LICENSE

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

