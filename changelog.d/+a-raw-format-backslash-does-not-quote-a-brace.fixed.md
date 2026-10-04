Raw Python format strings keep backslashes without consuming the format brace
that follows. Regex literals such as `rf"\{{{name}\}}"` retain doubled braces
and interpolation boundaries.
