/// Full keyid|challenge payload, without the outer |challstr| envelope.
bool isValidAuthChallenge(String value) =>
    value.length <= 4096 &&
    RegExp(r'^[0-9]+\|[^\s\x00-\x1f\x7f-\x9f]+$').stringMatch(value) == value;
