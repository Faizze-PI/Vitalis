import 'dart:convert';

bool exceedsUtf8Bytes(String value, int maximumBytes) =>
    utf8.encode(value).length > maximumBytes;

bool exceedsUnicodeScalars(String value, int maximumScalars) =>
    value.runes.length > maximumScalars;
