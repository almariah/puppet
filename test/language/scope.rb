#!/usr/bin/ruby

if __FILE__ == $0
    $:.unshift '../../lib'
    $:.unshift '..'
    $puppetbase = "../.."
end

require 'puppet'
require 'puppet/parser/interpreter'
require 'puppet/parser/parser'
require 'puppet/client'
require 'test/unit'
require 'puppettest'

# so, what kind of things do we want to test?

# we don't need to test function, since we're confident in the
# library tests.  We do, however, need to test how things are actually
# working in the language.

# so really, we want to do things like test that our ast is correct
# and test whether we've got things in the right scopes

class TestScope < Test::Unit::TestCase
	include ParserTesting

    def to_ary(hash)
        hash.collect { |key,value|
            [key,value]
        }
    end

    def test_variables
        scope = nil
        over = "over"

        scopes = []
        vars = []
        values = {}
        ovalues = []

        10.times { |index|
            # slap some recursion in there
            scope = Puppet::Parser::Scope.new(:parent => scope)
            scopes.push scope

            var = "var%s" % index
            value = rand(1000)
            ovalue = rand(1000)
            
            ovalues.push ovalue

            vars.push var
            values[var] = value

            # set the variable in the current scope
            assert_nothing_raised {
                scope.setvar(var,value)
            }

            # this should override previous values
            assert_nothing_raised {
                scope.setvar(over,ovalue)
            }

            assert_equal(value,scope.lookupvar(var))

            #puts "%s vars, %s scopes" % [vars.length,scopes.length]
            i = 0
            vars.zip(scopes) { |v,s|
                # this recurses all the way up the tree as necessary
                val = nil
                oval = nil

                # look up the values using the bottom scope
                assert_nothing_raised {
                    val = scope.lookupvar(v)
                    oval = scope.lookupvar(over)
                }

                # verify they're correct
                assert_equal(values[v],val)
                assert_equal(ovalue,oval)

                # verify that we get the most recent value
                assert_equal(ovalue,scope.lookupvar(over))

                # verify that they aren't available in upper scopes
                if parent = s.parent
                    val = nil
                    assert_nothing_raised {
                        val = parent.lookupvar(v)
                    }
                    assert_equal("", val, "Did not get empty string on missing var")

                    # and verify that the parent sees its correct value
                    assert_equal(ovalues[i - 1],parent.lookupvar(over))
                end
                i += 1
            }
        }
    end

    def test_declarative
        # set to declarative
        top = Puppet::Parser::Scope.new(:declarative => true)
        sub = Puppet::Parser::Scope.new(:parent => top)

        assert_nothing_raised {
            top.setvar("test","value")
        }
        assert_raise(Puppet::ParseError) {
            top.setvar("test","other")
        }
        assert_nothing_raised {
            sub.setvar("test","later")
        }
        assert_raise(Puppet::ParseError) {
            top.setvar("test","yeehaw")
        }
    end

    def test_notdeclarative
        # set to not declarative
        top = Puppet::Parser::Scope.new(:declarative => false)
        sub = Puppet::Parser::Scope.new(:parent => top)

        assert_nothing_raised {
            top.setvar("test","value")
        }
        assert_nothing_raised {
            top.setvar("test","other")
        }
        assert_nothing_raised {
            sub.setvar("test","later")
        }
        assert_nothing_raised {
            sub.setvar("test","yayness")
        }
    end

    def test_defaults
        scope = nil
        over = "over"

        scopes = []
        vars = []
        values = {}
        ovalues = []

        defs = Hash.new { |hash,key|
            hash[key] = Hash.new(nil)
        }

        prevdefs = Hash.new { |hash,key|
            hash[key] = Hash.new(nil)
        }

        params = %w{a list of parameters that could be used for defaults}

        types = %w{a set of types that could be used to set defaults}

        10.times { |index|
            scope = Puppet::Parser::Scope.new(:parent => scope)
            scopes.push scope

            tmptypes = []

            # randomly create defaults for a random set of types
            tnum = rand(5)
            tnum.times { |t|
                # pick a type
                #Puppet.debug "Type length is %s" % types.length
                #s = rand(types.length)
                #Puppet.debug "Type num is %s" % s
                #type = types[s]
                #Puppet.debug "Type is %s" % s
                type = types[rand(types.length)]
                if tmptypes.include?(type)
                    Puppet.debug "Duplicate type %s" % type
                    redo
                else
                    tmptypes.push type
                end

                Puppet.debug "type is %s" % type

                d = {}

                # randomly assign some parameters
                num = rand(4)
                num.times { |n|
                    param = params[rand(params.length)]
                    if d.include?(param)
                        Puppet.debug "Duplicate param %s" % param
                        redo
                    else
                        d[param] = rand(1000)
                    end
                }

                # and then add a consistent type
                d["always"] = rand(1000)

                d.each { |var,val|
                    defs[type][var] = val
                }

                assert_nothing_raised {
                    scope.setdefaults(type,to_ary(d))
                }
                fdefs = nil
                assert_nothing_raised {
                    fdefs = scope.lookupdefaults(type)
                }

                # now, make sure that reassignment fails if we're
                # in declarative mode
                assert_raise(Puppet::ParseError) {
                    scope.setdefaults(type,[%w{always funtest}])
                }

                # assert that we have collected the same values
                assert_equal(defs[type],fdefs)

                # now assert that our parent still finds the same defaults
                # it got last time
                if parent = scope.parent
                    unless prevdefs[type].nil?
                        assert_equal(prevdefs[type],parent.lookupdefaults(type))
                    end
                end
                d.each { |var,val|
                    prevdefs[type][var] = val
                }
            }
        }
    end
    
    def test_strinterp
        scope = Puppet::Parser::Scope.new()

        assert_nothing_raised {
            scope.setvar("test","value")
        }
        val = nil
        assert_nothing_raised {
            val = scope.strinterp("string ${test}")
        }
        assert_equal("string value", val)

        assert_nothing_raised {
            val = scope.strinterp("string ${test} ${test} ${test}")
        }
        assert_equal("string value value value", val)

        assert_nothing_raised {
            val = scope.strinterp("string $test ${test} $test")
        }
        assert_equal("string value value value", val)

        assert_nothing_raised {
            val = scope.strinterp("string \\$test")
        }
        assert_equal("string $test", val)

        assert_nothing_raised {
            val = scope.strinterp("\\$test string")
        }
        assert_equal("$test string", val)
    end

    # Test some of the host manipulations
    def test_hostlookup
        top = Puppet::Parser::Scope.new()

        # Create a deep scope tree, so that we know we're doing a deeply recursive
        # search.
        mid1 = Puppet::Parser::Scope.new(:parent => top)
        mid2 = Puppet::Parser::Scope.new(:parent => mid1)
        mid3 = Puppet::Parser::Scope.new(:parent => mid2)
        child1 = Puppet::Parser::Scope.new(:parent => mid3)
        mida = Puppet::Parser::Scope.new(:parent => top)
        midb = Puppet::Parser::Scope.new(:parent => mida)
        midc = Puppet::Parser::Scope.new(:parent => midb)
        child2 = Puppet::Parser::Scope.new(:parent => midc)

        # verify we can set a host
        assert_nothing_raised("Could not create host") {
            child1.setnode("testing", AST::Node.new(
                :type => "testing",
                :code => :notused
                )
            )
        }

        # Verify we cannot redefine it
        assert_raise(Puppet::ParseError, "Duplicate host creation succeeded") {
            child2.setnode("testing", AST::Node.new(
                :type => "testing",
                :code => :notused
                )
            )
        }

        # Now verify we can find the host again
        host = nil
        assert_nothing_raised("Host lookup failed") {
            hash = top.node("testing")
            host = hash[:node]
        }

        assert(host, "Could not find host")
        assert(host.code == :notused, "Host is not what we stored")
    end

    # Verify that two statements about a file within the same scope tree
    # will cause a conflict.
    def test_noconflicts
        filename = tempfile()
        children = []

        # create the parent class
        children << classobj("one", :code => AST::ASTArray.new(
            :children => [
                fileobj(filename, "owner" => "root")
            ]
        ))

        # now create a child class with differ values
        children << classobj("two",
            :code => AST::ASTArray.new(
                :children => [
                    fileobj(filename, "owner" => "bin")
                ]
        ))

        # Now call the child class
        assert_nothing_raised("Could not add AST nodes for calling") {
            children << AST::ObjectDef.new(
                :type => nameobj("two"),
                :name => nameobj("yayness"),
                :params => astarray()
            ) << AST::ObjectDef.new(
                :type => nameobj("one"),
                :name => nameobj("yayness"),
                :params => astarray()
            )
        }

        top = nil
        assert_nothing_raised("Could not create top object") {
            top = AST::ASTArray.new(
                :children => children
            )
        }

        objects = nil
        scope = nil

        # Here's where we should encounter the failure.  It should find that
        # it has already created an object with that name, and this should result
        # in some pukey-pukeyness.
        assert_raise(Puppet::ParseError) {
            scope = Puppet::Parser::Scope.new()
            objects = scope.evaluate(:ast => top)
        }
    end

    # Verify that statements about the same element within the same scope
    # cause a conflict.
    def test_failonconflictinsamescope
        filename = tempfile()
        children = []

        # Now call the child class
        assert_nothing_raised("Could not add AST nodes for calling") {
            children << fileobj(filename, "owner" => "root")
            children << fileobj(filename, "owner" => "bin")
        }

        top = nil
        assert_nothing_raised("Could not create top object") {
            top = AST::ASTArray.new(
                :children => children
            )
        }

        objects = nil
        scope = nil

        # Here's where we should encounter the failure.  It should find that
        # it has already created an object with that name, and this should result
        # in some pukey-pukeyness.
        assert_raise(Puppet::ParseError) {
            scope = Puppet::Parser::Scope.new()
            scope.top = true
            objects = scope.evaluate(:ast => top)
        }
    end

    # Verify that we override statements that we find within our scope
    def test_suboverrides
        filename = tempfile()
        children = []

        # create the parent class
        children << classobj("parent", :code => AST::ASTArray.new(
            :children => [
                fileobj(filename, "owner" => "root")
            ]
        ))

        # now create a child class with differ values
        children << classobj("child", :parentclass => nameobj("parent"),
            :code => AST::ASTArray.new(
                :children => [
                    fileobj(filename, "owner" => "bin")
                ]
        ))

        # Now call the child class
        assert_nothing_raised("Could not add AST nodes for calling") {
            children << AST::ObjectDef.new(
                :type => nameobj("child"),
                :name => nameobj("yayness"),
                :params => astarray()
            )
        }

        top = nil
        assert_nothing_raised("Could not create top object") {
            top = AST::ASTArray.new(
                :children => children
            )
        }

        objects = nil
        scope = nil
        assert_nothing_raised("Could not evaluate") {
            scope = Puppet::Parser::Scope.new()
            objects = scope.evaluate(:ast => top)
        }

        assert_equal(1, objects.length, "Returned too many objects: %s" %
            objects.inspect)

        assert_equal(1, objects[0].length, "Returned too many objects: %s" %
            objects[0].inspect)

        assert_nothing_raised {
            file = objects[0][0]
            assert_equal("bin", file["owner"], "Value did not override correctly")
        }
    end
    
    def test_multipletypes
        scope = Puppet::Parser::Scope.new()
        children = []

        # create the parent class
        children << classobj("aclass")
        children << classobj("aclass")
        top = nil
        assert_nothing_raised("Could not create top object") {
            top = AST::ASTArray.new(
                :children => children
            )
        }

        scope = nil
        assert_raise(Puppet::ParseError) {
            scope = Puppet::Parser::Scope.new()
            objects = top.evaluate(:scope => scope)
        }
    end

    # Verify that definitions have a different context than classes.
    def test_newsubcontext
        filename = tempfile()
        children = []

        # Create a component
        children << compobj("comp", :code => AST::ASTArray.new(
            :children => [
                fileobj(filename, "owner" => "root" )
            ]
        ))

        # Now create a class that modifies the same file and also
        # calls the component
        children << classobj("klass", :code => AST::ASTArray.new(
            :children => [
                fileobj(filename, "owner" => "bin" ),
                AST::ObjectDef.new(
                    :type => nameobj("comp"),
                    :params => astarray()
                )
            ]
        ))

        # Now call the class
        children << AST::ObjectDef.new(
            :type => nameobj("klass"),
            :params => astarray()
        )

        top = nil
        assert_nothing_raised("Could not create top object") {
            top = AST::ASTArray.new(
                :children => children
            )
        }

        trans = nil
        scope = nil
        #assert_nothing_raised {
        assert_raise(Puppet::ParseError, "A conflict was allowed") {
            scope = Puppet::Parser::Scope.new()
            trans = scope.evaluate(:ast => top)
        }
        #    scope = Puppet::Parser::Scope.new()
        #    trans = scope.evaluate(:ast => top)
        #}
    end

    def test_defaultswithmultiplestatements
        path = tempfile()

        stats = []
        stats << defaultobj("file", "group" => "root")
        stats << fileobj(path, "owner" => "root")
        stats << fileobj(path, "mode" => "755")

        top = AST::ASTArray.new(
            :file => __FILE__,
            :line => __LINE__,
            :children => stats
        )
        scope = Puppet::Parser::Scope.new()
        trans = nil
        assert_nothing_raised {
            trans = scope.evaluate(:ast => top)
        }

        obj = trans.find do |obj| obj.is_a? Puppet::TransObject end

        assert(obj, "Could not retrieve file obj")
        assert_equal("root", obj["group"], "Default did not take")
        assert_equal("root", obj["owner"], "Owner did not take")
        assert_equal("755", obj["mode"], "Mode did not take")
    end

    def test_validclassnames
        scope = Puppet::Parser::Scope.new()

        ["a class", "Class", "a.class"].each do |bad|
            assert_raise(Puppet::ParseError, "Incorrectly allowed %s" % bad.inspect) do
                scope.setclass(object_id, bad)
            end
        end

        ["a-class", "a_class", "class", "yayNess"].each do |good|
            assert_nothing_raised("Incorrectly banned %s" % good.inspect) do
                scope.setclass(object_id, good)
            end
        end

    end

    def test_tagfunction
        scope = Puppet::Parser::Scope.new()
        
        assert_nothing_raised {
            scope.function_tag(["yayness", "booness"])
        }

        assert(scope.classlist.include?("yayness"), "tag 'yayness' did not get set")
        assert(scope.classlist.include?("booness"), "tag 'booness' did not get set")

        # Now verify that the 'tagged' function works correctly
        assert(scope.function_tagged("yayness"),
            "tagged function incorrectly returned false")
        assert(scope.function_tagged("booness"),
            "tagged function incorrectly returned false")

        assert(! scope.function_tagged("funtest"),
            "tagged function incorrectly returned true")
    end

    def test_includefunction
        scope = Puppet::Parser::Scope.new()

        one = tempfile()
        two = tempfile()

        children = []

        children << classobj("one", :code => AST::ASTArray.new(
            :children => [
                fileobj(one, "owner" => "root")
            ]
        ))

        children << classobj("two", :code => AST::ASTArray.new(
            :children => [
                fileobj(two, "owner" => "root")
            ]
        ))

        children << Puppet::Parser::AST::Function.new(
            :name => "include",
            :ftype => :statement,
            :arguments => AST::ASTArray.new(
                :children => [nameobj("one"), nameobj("two")]
            )
        )

        top = AST::ASTArray.new(:children => children)

        #assert_nothing_raised {
        #    scope.function_include(["one", "two"])
        #}

        assert_nothing_raised {
            scope.evaluate(:ast => top)
        }


        assert(scope.classlist.include?("one"), "tag 'one' did not get set")
        assert(scope.classlist.include?("two"), "tag 'two' did not get set")

        # Now verify that the 'tagged' function works correctly
        assert(scope.function_tagged("one"),
            "tagged function incorrectly returned false")
        assert(scope.function_tagged("two"),
            "tagged function incorrectly returned false")
    end

    def test_definedfunction
        scope = Puppet::Parser::Scope.new()

        one = tempfile()
        two = tempfile()

        children = []

        children << classobj("one", :code => AST::ASTArray.new(
            :children => [
                fileobj(one, "owner" => "root")
            ]
        ))

        children << classobj("two", :code => AST::ASTArray.new(
            :children => [
                fileobj(two, "owner" => "root")
            ]
        ))

        top = AST::ASTArray.new(:children => children)

        top.evaluate(:scope => scope)

        assert_nothing_raised {
            %w{one two file user}.each do |type|
                assert(scope.function_defined([type]),
                    "Class #{type} was not considered defined")
            end

            assert(!scope.function_defined(["nopeness"]),
                "Class 'nopeness' was incorrectly considered defined")
        }


    end

    # Make sure components acquire defaults.
    def test_defaultswithcomponents
        children = []

        # Create a component
        filename = tempfile()
        args = AST::ASTArray.new(
            :file => tempfile(),
            :line => rand(100),
            :children => [nameobj("argument")]
        )
        children << compobj("comp", :args => args, :code => AST::ASTArray.new(
            :children => [
                fileobj(filename, "owner" => varref("argument") )
            ]
        ))

        # Create a default
        children << defaultobj("comp", "argument" => "yayness")

        # lastly, create an object that calls our third component
        children << objectdef("comp", "boo", {"argument" => "parentfoo"})

        trans = assert_evaluate(children)

        flat = trans.flatten

        assert(!flat.empty?, "Got no objects back")

        assert_equal("parentfoo", flat[0]["owner"], "default did not take")
    end

    # Make sure we know what we consider to be truth.
    def test_truth
        assert_equal(true, Puppet::Parser::Scope.true?("a string"),
            "Strings not considered true")
        assert_equal(true, Puppet::Parser::Scope.true?(true),
            "True considered true")
        assert_equal(false, Puppet::Parser::Scope.true?(""),
            "Empty strings considered true")
        assert_equal(false, Puppet::Parser::Scope.true?(false),
            "false considered true")
    end

    # Verify scope context is handled correctly.
    def test_scopeinside
        scope = Puppet::Parser::Scope.new()

        one = :one
        two = :two

        # First just test the basic functionality.
        assert_nothing_raised {
            scope.inside :one do
                assert_equal(:one, scope.inside, "Context did not get set")
            end
            assert_nil(scope.inside, "Context did not revert")
        }

        # Now make sure error settings work.
        assert_raise(RuntimeError) {
            scope.inside :one do
                raise RuntimeError, "This is a failure, yo"
            end
        }
        assert_nil(scope.inside, "Context did not revert")

        # Now test it a bit deeper in.
        assert_nothing_raised {
            scope.inside :one do
                scope.inside :two do
                    assert_equal(:two, scope.inside, "Context did not get set")
                end
                assert_equal(:one, scope.inside, "Context did not get set")
            end
            assert_nil(scope.inside, "Context did not revert")
        }

        # And lastly, check errors deeper in
        assert_nothing_raised {
            scope.inside :one do
                begin
                    scope.inside :two do
                        raise "a failure"
                    end
                rescue
                end
                assert_equal(:one, scope.inside, "Context did not get set")
            end
            assert_nil(scope.inside, "Context did not revert")
        }

    end

    if defined? ActiveRecord
    # Verify that we recursively mark as collectable the results of collectable
    # components.
    def test_collectablecomponents
        children = []

        args = AST::ASTArray.new(
            :file => tempfile(),
            :line => rand(100),
            :children => [nameobj("arg")]
        )
        # Create a top-level component
        children << compobj("one", :args => args)

        # And a component that calls it
        children << compobj("two", :args => args, :code => AST::ASTArray.new(
            :children => [
                objectdef("one", "ptest", {"arg" => "parentfoo"})
            ]
        ))

        # And then a third component that calls the second
        children << compobj("three", :args => args, :code => AST::ASTArray.new(
            :children => [
                objectdef("two", "yay", {"arg" => "parentfoo"})
            ]
        ))

        # lastly, create an object that calls our third component
        obj = objectdef("three", "boo", {"arg" => "parentfoo"})

        # And mark it as collectable
        obj.collectable = true

        children << obj

        top = nil
        assert_nothing_raised("Could not create top object") {
            top = AST::ASTArray.new(
                :children => children
            )
        }

        trans = nil
        scope = nil
        assert_nothing_raised {
            scope = Puppet::Parser::Scope.new()
            trans = scope.evaluate(:ast => top)
        }

        %w{file}.each do |type|
            objects = scope.exported(type)

            assert(!objects.empty?, "Did not get an exported %s" % type)
        end
    end

    # Verify that we can both store and collect an object in the same
    # run, whether it's in the same scope as a collection or a different
    # scope.
    def test_storeandcollect
        Puppet[:storeconfigs] = true
        Puppet::Rails.clear
        Puppet::Rails.init
        sleep 1
        children = []
        file = tempfile()
        File.open(file, "w") { |f|
            f.puts "
class yay {
    @host { myhost: ip => \"192.168.0.2\" }
}
include yay
@host { puppet: ip => \"192.168.0.3\" }
host <||>"
        }

        interp = nil
        assert_nothing_raised {
            interp = Puppet::Parser::Interpreter.new(
                :Manifest => file,
                :UseNodes => false,
                :ForkSave => false
            )
        }

        objects = nil
        # We run it twice because we want to make sure there's no conflict
        # if we pull it up from the database.
        2.times { |i|
            assert_nothing_raised {
                objects = interp.run("localhost", {})
            }

            flat = objects.flatten

            %w{puppet myhost}.each do |name|
                assert(flat.find{|o| o.name == name }, "Did not find #{name}")
            end
        }
    end

    # Verify that we cannot override differently exported objects
    def test_exportedoverrides
        filename = tempfile()
        children = []

        obj = fileobj(filename, "owner" => "root")
        obj.collectable = true
        # create the parent class
        children << classobj("parent", :code => AST::ASTArray.new(
            :children => [
                obj
            ]
        ))

        # now create a child class with differ values
        children << classobj("child", :parentclass => nameobj("parent"),
            :code => AST::ASTArray.new(
                :children => [
                    fileobj(filename, "owner" => "bin")
                ]
        ))

        # Now call the child class
        assert_nothing_raised("Could not add AST nodes for calling") {
            children << AST::ObjectDef.new(
                :type => nameobj("child"),
                :name => nameobj("yayness"),
                :params => astarray()
            )
        }

        top = nil
        assert_nothing_raised("Could not create top object") {
            top = AST::ASTArray.new(
                :children => children
            )
        }

        objects = nil
        scope = nil
        assert_raise(Puppet::ParseError, "Incorrectly allowed override") {
            scope = Puppet::Parser::Scope.new()
            objects = scope.evaluate(:ast => top)
        }
    end
    else
        $stderr.puts "No ActiveRecord -- skipping collection tests"
    end
end
