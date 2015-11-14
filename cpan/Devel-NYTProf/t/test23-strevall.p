# test handling of string eval 'file names' that don't include the
# invoking filename (normally added when $^P & 0x100 is true).

shift;

# fake an eval (using a #line directive) that doesn't match the
# usual "(eval N)[file:line]" syntax:
#line 42 "(eval 142)"
# [stats for the line below won't appear in reports because as far as perl is
# concerned the rest of this file isn't actually part of this file, but is
# actually part of a file called "(eval 142)"]
242;
