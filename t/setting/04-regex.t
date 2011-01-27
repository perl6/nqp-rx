#! nqp

pir::load_bytecode('nqp-setting.pbc');

plan(4);

my @a := split(/\d/, 'a23b5d');
ok(+@a == 4, 'split produced 4 chunks');
ok((@a.join('!') eq 'a!!b!d'), 'got right chunks');

@a := split('/', 'foo/bar/baz');
ok(+@a == 3, 'split produced 3 chunks');
ok((@a.join('!') eq 'foo!bar!baz'), 'got right chunks');


# vim: ft=perl6
