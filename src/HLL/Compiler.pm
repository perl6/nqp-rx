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

    method autoprint($value) {
        pir::say(~$value);
    }

    method interactive(*%adverbs) {
        my $target := pir::downcase(%adverbs<target>);

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
                my %*REPL_NEXT;
                {
                    $output := self.eval($code, :repl(1), |%adverbs);
                    CATCH {
                        pir::print(~$! ~ "\n");
                        next;
                    }
                };
                next if pir::isnull($output);

                for %*REPL_NEXT -> $kv { %adverbs{$kv.key} := $kv.value }

                if !$target {
                    self.autoprint($output);
                } elsif $target eq 'pir' {
                   pir::say($output);
                } else {
                   self.dumper($output, $target, |%adverbs);
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

        if pir::defined(%adverbs<outer_ctx>) {
            my @ns := pir::getattribute__PPs(%adverbs<outer_ctx>,
                'current_namespace').get_name;
            @ns.shift;
            $block.namespace(@ns);
        }

        for %symbols -> $kv {
            my %v := $kv.value;
            $block.symbol($kv.key, |%v);
            $cb($kv) if pir::defined($cb);
        }
    }

    # Mark symbols for use; this will be called automatically, but you want to
    # call it yourself if you want to continue an inner scope.
    method set_new_symtable($st) {
        %*REPL_NEXT<outer_symtable> := $st
            if %*COMPILING<%?OPTIONS><repl>;
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

    method add_context_extraction_hook($past) {
        return 0 unless %*COMPILING<%?OPTIONS><repl>;

        $past.unshift(PAST::Op.new(
                :pasttype('bind'),
                PAST::Var.new(
                    :scope('keyed'),
                    PAST::Var.new(
                        :scope('contextual'),
                        :name('%*REPL_NEXT') ),
                    "outer_ctx"),
                PAST::Var.new(
                    :scope('keyed'),
                    PAST::Op.new( :pasttype('pirop'),
                                  :pirop('getinterp P') ),
                    PAST::Val.new( :value('context') ) ) ));
        $past.unshift(PAST::Block.new());
    }

    method wrap_past($past) {
        my $target := $past;
        if pir::defined($past<mainline>) {
            $target := $past<mainline>;
        } elsif !$past.isa(PAST::Block) {
            $past := PAST::Block.new(
                :blocktype('immediate'),
                $past
            );
        }

        self.add_context_extraction_hook($target);
        self.install_outer_lexicals($target);
        self.set_new_symtable($target.symtable);

        $past;
    }

    method post($past, *%adverbs) {
        my $SUPER := P6metaclass.get_parrotclass(PCT::HLLCompiler);
        $SUPER.find_method('post')(self, self.wrap_past($past), |%adverbs);
    }

    method eval($code, *@args, *%adverbs) {
        my $output; my $outer;
        $output := self.compile($code, |%adverbs);

        if !pir::isa($output, 'String')
                && %adverbs<target> eq '' {

            if pir::defined(%adverbs<outer_ctx>) {
                # TODO: We ought to be passing the entire context here,
                # but this works for now (arguably a Parrot bug).
                my $sub := pir::getattribute__PPS(%adverbs<outer_ctx>,
                    "current_sub");
                $output[0].set_outer($sub);
            }

            pir::trace(%adverbs<trace>) if %adverbs<trace>;
            $output := $output[0]();
            pir::trace(0) if %adverbs<trace>;
        }

        $output;
    }
}
