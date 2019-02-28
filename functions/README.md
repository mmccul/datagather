# What lives here

Each file here should contain a single function.  The function should provide
an interface for manipulating the data.

# Variable naming

Because there are no local variables in POSIX sh, we need a way to ensure
variable name uniqueness.  Use the literal string of the name of the function,
preceeded by an underscore and separated from the variable name by another
underscore.

## Example

If the fucntion is named **printxml**, then a variable intended solely for that
function, known as **message** is to have the full variable name of
**_printxml_message**.  

## Free variables

Variables no longer needed should be **unset** to further reduce the chance
that they are lost.
