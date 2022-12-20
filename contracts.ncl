let predicate | doc "Various predicates used to define contracts"
  = {
    is_plain_string = builtin.is_str

    , is_nix_path
        = fun x => builtin.is_record x &&
                   record.has_field "type" x &&
                   x.type == `nixPath

    , is_nix_derivation
        = fun x => builtin.is_record x &&
                   record.has_field "type" x &&
                   x.type == `nixDerivation

    , is_nickel_derivation = fun x =>
      builtin.is_record x &&
      record.has_field "type" x &&
      is_derivation_type x.type

    , is_derivation = fun x =>
      is_nickel_derivation x ||
      is_nix_derivation x

    , is_string_fragment = fun x =>
      is_derivation x ||
      is_plain_string x ||
      is_nix_path x

    , is_derivation_type = fun x =>
      x == `nickelPackage || x == `nickelShell
  } in

let mk_nix_string  = fun fs => {
  type = `nixString, fragments = fs,
} in

{
  # Nix may require name, version, etc. to have a certain format, but we're not sure. 
  # TODO: refine those contracts
  Name = Str,
  Version = Str,
  # TODO: For now, we use Str, but should we have enums tags for arch and os
  # instead?
  System = {arch | Str, os | Str},

  # TODO: more precise contract
  Derivation
    | m%" 
        Contract representing either a Nix derivation (evaluated and imported
from the Nix world) or a derivation defined in Nickel.
      "%
    = Dyn,

  NixStringFragment
    | doc "A fragment of a Nix string (or a string with context). See `NixString`"
    = contract.from_predicate predicate.is_string_fragment,

  NixString
   | doc m%%"
      Nix string with a
      [context](https://shealevy.com/blog/2018/08/05/understanding-nixs-string-context/)
      tracking the dependencies that need to be built before the string can make
      sense.

      Anything expecting a `NixString` accepts a pure Nickel string as well. A
      `NixString` also accepts a Nix string fragment, which can be a Nickel
      derivation, a Nickel derivation, a Nix path (built from `lib.import_file`), pure
      Nickel strings, and maybe more in the future.

      A `NixString` accepts any sequence of Nix string fragment as well.

      A `NixString` is best constructed using the symbolic string syntax. See
      the Nickel example below.

      # Nix string context

      In Nix, when one writes:

      ```nix
      shellHook = ''
        echo "Development shell"
        ${pkgs.hello}/bin/hello
      ''
      ```

      Nix automatically deduces that this shell depends on the `hello`
      package. Nickel doesn't have string contexts, and given the way values
      are passed from and to Nix, this dependency information is just lost when
      using bare strings.

      Sometimes, you may not need the context: if `hello` is explicitly part
      of the inputs, you can use a plain string in a Nickel
      expression as well:

      ```nickel
      shellHook = m%"
        echo "Development shell"
        %{pkgs.hello.outputPath}/bin/hello
      "%
      ```

      # Example

      However, if you need the dependency to `hello` to be automatically
      deduced, you can use symbolic strings whenever a field has a `NixString`
      contract attached. The result will be elaborated as a richer structure,
      carrying the context, and will be reconstructed on the Nix side.

      To do so, juste use the multiline string syntax, but with an `s` prefix
      instead (**Warning**: the `s` prefix is as of now temporary, and subject
      to change in the future): 

      ```nickel
      shellHook = s%"
        echo "Development shell"
        %{pkgs.hello}/bin/hello
      "%
      ```

      Note that:
        - we've used the symbolic string syntax `s%"`
        - instead of `hello.outputPath`, we've interpolated `hello` directly,
          which is a derivation, and not a string

      Within a `NixString`, you can interpolate a Nix String, or a Nix string
      fragment, that is a Nix derivation, a Nickel derivation, a Nix path (built from
      `lib.import_file`), pure Nickel strings, and maybe more in the future.
    "%%
    = fun label value =>
      # We accept a single string fragment (a plain string, a derivation or a
      # Nix path). We normalize it by wrapping it as a one-element array
      if predicate.is_string_fragment value then
        mk_nix_string [contract.apply NixStringFragment label value]
      else
        #TODO: we should use contract.apply, otherwise the error reporting is
        # off, but doing so makes Nickel panic for now. Until the bug is
        # fixed, we have to resort to this contract application
        (value | Array NixStringFragment)
        |> mk_nix_string,
  
  NixDerivation | doc "A derivation coming from the Nix world"
    = {
    drvPath | Str,
    outputName | Str,
    type = `nixDerivation,
  },

  NickelDerivation
    | doc m%"
        The basic, low-level interface for a symbolic derivation. A NickelPkg is
        intenteded to be passed (exported) to the Nix side, which will take care
        of actually building it.
      "%
    = {
      name
        | doc "The name of the package."
        | Name,
      # in Nix, the version isn't actually strictly required by the interface of
      # derivation. But we probably want to impose it if we are to redefine the
      # API on the Nickel side.
      version
        | doc "The version of the package."
        | optional
        | Version,
      dependencies
        | doc "The dependencies of the package."
        | Array Derivation
        | default = [],
      system
        | doc "The system to build the package on."
        | System
        | default = {arch = "x86_64", os = "linux"},
      build_command
        | doc "The build command to execute."
        | {
          cmd | NixString,
          args | Array NixString
        },
      env
        | doc "Set additional environment variables for the builder."
        | {_: NixString},
      # "derivation"
      type | force = `nickelDerivation,
  },


  Params | doc "The parameters provided to the Nickel expression"
    = {
    system | System,
    inputs | {_: Derivation},
    nix | {..},
  },

  NickelInputSpec | doc "The specification of an input in a Nickel expression"
  = {
    input | Str
          | default = "nixpkgs",
    # TODO: precise contract. We want to allow a path if input == "sources"
    ..
  },

  # TODO: have the actual contract for the result of an expression. It's pretty
  # open (could be an integer, a derivation, a record of derivations, etc.) but
  # still obey some rules: if the `type` field is set to a known predefined
  # value, then the record must have a certain shape.
  # The contract must be: what the Nix side of the code can "parse" without
  # erroring out.
  NickelExpressionResult = Dyn,

  NickelExpression | doc "A Nickel expression"
    = {
    inputs_spec | {_ : NickelInputSpec},
    output | Params -> NickelExpressionResult,
  },

  NixPath = {
    type | force = `nixPath,
    path | Str,
  }
}