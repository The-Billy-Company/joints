<?php

class Str
{
    public static function limit($value, $limit, $end)
    {
        $trimmed = rtrim($value);

        return preg_replace('/(.*)\s.*/', '$1', $trimmed).$end;
    }
}
