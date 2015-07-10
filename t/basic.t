#!/usr/bin/env perl
use strictures 2;

use Test::More;

use Web::Starch;

my $db_file = 'test.db';
unlink( $db_file ) if -f $db_file;

my $starch = Web::Starch->new(
    store => {
        class  => '::DBI',
        dbh => [
            'dbi:SQLite:dbname=test.db',
            '',
            '',
            { RaiseError => 1 },
        ],
    },
);

my $store = $starch->store();
my $dbh = $store->dbh();

my $table = $store->table();
my $key_column = $store->key_column();
my $data_column = $store->data_column();
my $expiration_column = $store->expiration_column();

$dbh->do(qq[
    CREATE TABLE $table (
        $key_column TEXT NOT NULL PRIMARY KEY,
        $data_column TEXT NOT NULL,
        $expiration_column INTEGER NOT NULL
    )
]);

is( $store->get('foo'), undef, 'get an unknown key' );

$store->set( 'foo', {bar=>6}, 10 );
isnt( $store->get('foo'), undef, 'add, then get a known key' );
is( $store->get('foo')->{bar}, 6, 'known key data value' );

$store->set( 'foo', {bar=>3}, 20 );
is( $store->get('foo')->{bar}, 3, 'update, then get a known key' );

$store->remove( 'foo' );
is( $store->get('foo'), undef, 'get a removed key' );

done_testing();
