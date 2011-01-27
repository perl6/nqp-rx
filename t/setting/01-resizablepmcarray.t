#! nqp

pir::load_bytecode('nqp-setting.pbc');

my @array := <0 1 2>;
my @reversed := @array.reverse();

plan(16);

ok( @reversed[0] == 2, 'First element correct');
ok( @reversed[1] == 1, 'Second element correct');
ok( @reversed[2] == 0, 'Third element correct');

my $join := @array.join('|');
ok( $join eq '0|1|2', 'Join elements');
$join := @array.join();
ok( $join eq '012', 'Join with default separator');

ok( join(':', 'foo', 'bar', 'baz') eq 'foo:bar:baz', 'Join as standalone function');

my @test := <apple banana cherry>;
ok( @test.exists(2), 'Item exists at @test[2]' );
ok( !@test.exists(3), 'Item does not exist at @test[3]');
@test.delete(1);
ok( @test[1] eq 'cherry', '@test[1] was deleted');
ok( +@test == 2, '@test[1] has two items');
ok( !@test.exists(2), '@test[2] no longer exists');

@test := <1 2 3>;
my @res := @test.map(-> $a { $a~$a; });
ok( +@res == 3, 'Map produced same number of elements');
ok( @res.join() eq '112233', 'Map produced correct elements');

@res := @test.grep(-> $a { $a % 2 });
ok( +@res == 2, 'Grep produced correct number of elements');
ok( @res[0] == 1, 'Grep produced correct elements');
ok( @res[1] == 3, 'Grep produced correct elements');

# vim: ft=perl6
