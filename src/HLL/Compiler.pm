INIT {
    pir::load_bytecode('PCT/HLLCompiler.pbc');
}


class HLL::Compiler is PCT::HLLCompiler {

    has $!language;

    INIT {
        HLL::Compiler.language('parrot');
    }
    
    my sub value_type($value) {
        pir::isa($value, 'NameSpace') 
        ?? 'namespace'
        !! (pir::isa($value, 'Sub') ?? 'sub' !! 'var')
    }
        
    method get_exports($module, :$tagset, *@symbols) {
        # convert a module name to something hash-like, if needed
        if (!pir::does($module, 'hash')) {
            $module := self.get_module($module);
        }

        $tagset := $tagset // (@symbols ?? 'ALL' !! 'DEFAULT');
        my %exports;
        my %source := $module{'EXPORT'}{~$tagset};
        if !pir::defined(%source) {
            %source := $tagset eq 'ALL' ?? $module !! {};
        }
        if @symbols {
            for @symbols {
                my $value := %source{~$_};
                %exports{value_type($value)}{$_} := $value;
            }
        }
        else {
            for %source {
                my $value := $_.value;
                %exports{value_type($value)}{$_.key} := $value;
            }
        }
        %exports;
    }

    method get_module($name) {
        my @name := self.parse_name($name);
        @name.unshift(pir::downcase($!language));
        pir::get_root_namespace__PP(@name);
    }

    method language($name?) {
        if $name {
            $!language := $name;
            pir::compreg__0sP($name, self);
        }
        $!language;
    }

    method load_module($name) {
        my $base := pir::join('/', self.parse_name($name));
        my $loaded := 0;
        try { pir::load_bytecode("$base.pbc"); $loaded := 1 };
        unless $loaded { pir::load_bytecode("$base.pir"); $loaded := 1 }
        self.get_module($name);
    }

    method import($target, %exports) {
        for %exports {
            my $type := $_.key;
            my %items := $_.value;
            if pir::can(self, "import_$type") {
                for %items { self."import_$type"($target, $_.key, $_.value); }
            }
            elsif pir::can($target, "add_$type") {
                for %items { $target."add_$type"($_.key, $_.value); }
            }
            else {
                for %items { $target{~$_.key} := $_.value; }
            }
        }
    }

    method interactive(*%adverbs) {
        my $target := pir::downcase(%adverbs<target>);
        my &*REPL_LAST_SUB;

        pir::printerr__vS(self.commandline_banner);

        my $stdin := pir::getstdin__P();
        my $encoding := ~%adverbs<encoding>;
        if $encoding && $encoding ne 'fixed_8' {
            $stdin.encoding($encoding);
        }

        while 1 {
            last unless $stdin;

            my $prompt := self.commandline_prompt // '> ';
            my $code := $stdin.readline_interactive(~$prompt);

            last if pir::isnull($code);

            if $code {
                $code := $code ~ "\n";
                my $output;
                my $*NEW_OUTER_SYMTABLE;
                my $*NEW_OUTER_CONTEXT;
                {
                    $output := self.eval($code, |%adverbs);
                    %adverbs<outer_ctx> := $*NEW_OUTER_CONTEXT
                        if pir::defined($*NEW_OUTER_CONTEXT);
                    %adverbs<outer_symtable> := $*NEW_OUTER_SYMTABLE
                        if pir::defined($*NEW_OUTER_SYMTABLE);
                    CATCH {
                        pir::print(~$! ~ "\n");
                        next;
                    }
                };
                next if pir::isnull($output);

                if $target {
                    if $target eq 'pir' {
                        say($output);
                    } else {
                        self.dumper($output, $target, |%adverbs);
                    }
                }
            }
        }
    }

    # This will be called automatically.  You might want to call it early
    # if you're introspecting the symbol table, like Rakudo does.
    method install_outer_lexicals($block, $cb?) {
        my %adverbs := %*COMPILING<%?OPTIONS>;

        my %symbols :=
            pir::defined(%adverbs<outer_symtable>) ??
                %adverbs<outer_symtable> !!
            pir::defined(%adverbs<outer_ctx>) ??
                self.reconstruct_symbols(%adverbs<outer_ctx><current_sub>) !!
            {};

        for %symbols -> $kv {
            my %v := $kv.value;
            $block.symbol($kv.key, |%v);
            $cb($kv) if pir::defined($cb);
        }
    }

    # Mark symbols for use; this will be called automatically, but you want to
    # call it yourself if you want to continue an inner scope.
    method set_new_symtable($st) {
        try { $*NEW_OUTER_SYMTABLE := $st };
    }

    # Mostly important for evals called from compiled code, when the PAST
    # is long since gone
    method reconstruct_symbols($outer) {
        my %tab;
        my %entry;
        %entry<scope> := 'lexical';

        while pir::defined($outer) {
            my $lexinfo := $outer.get_lexinfo;

            for $lexinfo -> $kv {
                %tab{$kv.key} := %entry;
            }

            $outer := $outer.get_outer;
        }

        %tab;
    }

    method post($past, *%adverbs) {
        if (!$past.isa(PAST::Block)) {
            $past := PAST::Block.new(
                :blocktype('immediate'),
                $past
            );
        }

        try {
            $*NEW_OUTER_CONTEXT;
            $past.unshift(PAST::Op.new(
                    :pasttype('bind'),
                    PAST::Var.new( :name('$*NEW_OUTER_CONTEXT'),
                                   :scope('contextual') ),
                    PAST::Var.new(
                        :scope('keyed'),
                        PAST::Op.new( :pasttype('pirop'),
                                      :pirop('getinterp P') ),
                        PAST::Val.new( :value('context') ) ) ));
        }

        self.install_outer_lexicals($past);

        my %symtab := $past.symtable;
        # note that the grammar actions may already have picked a symtable
        try { $*NEW_OUTER_SYMTABLE := %symtab
                  unless pir::defined($*NEW_OUTER_SYMTABLE); };

        my $SUPER := P6metaclass.get_parrotclass(PCT::HLLCompiler);
        $SUPER.find_method('post')(self, $past, |%adverbs);
    }

    method eval($code, *@args, *%adverbs) {
        my $output; my $outer;
        $output := self.compile($code, |%adverbs);

        if !pir::isa($output, 'String')
                && %adverbs<target> eq '' {

            if pir::defined(%adverbs<outer_ctx>) {
                $output[0].set_outer(%adverbs<outer_ctx>);
            }

            pir::trace(%adverbs<trace>);
            $output := $output[0]();
            pir::trace(0);
        }

        $output;
    }
}
