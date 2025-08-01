const { hideFromStack } = require("internal/shared");

const RegExpPrototypeExec = RegExp.prototype.exec;
const ArrayIsArray = Array.isArray;
const ObjectPrototypeHasOwnProperty = Object.prototype.hasOwnProperty;

const tokenRegExp = /^[\^_`a-zA-Z\-0-9!#$%&'*+.|~]+$/;
/**
 * Verifies that the given val is a valid HTTP token
 * per the rules defined in RFC 7230
 * See https://tools.ietf.org/html/rfc7230#section-3.2.6
 */
function checkIsHttpToken(val) {
  return RegExpPrototypeExec.$call(tokenRegExp, val) !== null;
}

/*
  The rules for the Link header field are described here:
  https://www.rfc-editor.org/rfc/rfc8288.html#section-3

  This regex validates any string surrounded by angle brackets
  (not necessarily a valid URI reference) followed by zero or more
  link-params separated by semicolons.
*/
const linkValueRegExp = /^(?:<[^>]*>)(?:\s*;\s*[^;"\s]+(?:=(")?[^;"\s]*\1)?)*$/;
function validateLinkHeaderFormat(value, name) {
  if (typeof value === "undefined" || !RegExpPrototypeExec.$call(linkValueRegExp, value)) {
    throw $ERR_INVALID_ARG_VALUE(
      name,
      value,
      `must be an array or string of format "</styles.css>; rel=preload; as=style"`,
    );
  }
}

function validateLinkHeaderValue(hints) {
  if (typeof hints === "string") {
    validateLinkHeaderFormat(hints, "hints");
    return hints;
  } else if (ArrayIsArray(hints)) {
    const hintsLength = hints.length;
    let result = "";

    if (hintsLength === 0) {
      return result;
    }

    for (let i = 0; i < hintsLength; i++) {
      const link = hints[i];
      validateLinkHeaderFormat(link, "hints");
      result += link;

      if (i !== hintsLength - 1) {
        result += ", ";
      }
    }

    return result;
  }

  throw $ERR_INVALID_ARG_VALUE(
    "hints",
    hints,
    `must be an array or string of format "</styles.css>; rel=preload; as=style"`,
  );
}

function validateString(value, name) {
  if (typeof value !== "string") throw $ERR_INVALID_ARG_TYPE(name, "string", value);
}

function validateFunction(value, name) {
  if (typeof value !== "function") throw $ERR_INVALID_ARG_TYPE(name, "function", value);
}

function validateBoolean(value, name) {
  if (typeof value !== "boolean") throw $ERR_INVALID_ARG_TYPE(name, "boolean", value);
}

function validateUndefined(value, name) {
  if (value !== undefined) throw $ERR_INVALID_ARG_TYPE(name, "undefined", value);
}

function validateInternalField(object, fieldKey, className) {
  if (typeof object !== "object" || object === null || !ObjectPrototypeHasOwnProperty.$call(object, fieldKey)) {
    throw $ERR_INVALID_ARG_TYPE("this", className, object);
  }
}

hideFromStack(validateLinkHeaderValue, validateInternalField);
hideFromStack(validateString, validateFunction, validateBoolean, validateUndefined);

export default {
  /** (value, name) */
  validateObject: $newCppFunction("NodeValidator.cpp", "jsFunction_validateObject", 2),
  validateLinkHeaderValue: validateLinkHeaderValue,
  checkIsHttpToken: checkIsHttpToken,
  /** `(value, name, min, max)` */
  validateInteger: $newCppFunction("NodeValidator.cpp", "jsFunction_validateInteger", 0),
  /** `(value, name, min, max)` */
  validateNumber: $newCppFunction("NodeValidator.cpp", "jsFunction_validateNumber", 0),
  /** `(value, name)` */
  validateString,
  /** `(number, name)` */
  validateFiniteNumber: $newCppFunction("NodeValidator.cpp", "jsFunction_validateFiniteNumber", 0),
  /** `(number, name, lower, upper, def)` */
  checkRangesOrGetDefault: $newCppFunction("NodeValidator.cpp", "jsFunction_checkRangesOrGetDefault", 0),
  /** `(value, name)` */
  validateFunction,
  /** `(value, name)` */
  validateBoolean,
  /** `(port, name = 'Port', allowZero = true)` */
  validatePort: $newCppFunction("NodeValidator.cpp", "jsFunction_validatePort", 0),
  /** `(signal, name)` */
  validateAbortSignal: $newCppFunction("NodeValidator.cpp", "jsFunction_validateAbortSignal", 0),
  /** `(value, name, minLength = 0)` */
  validateArray: $newCppFunction("NodeValidator.cpp", "jsFunction_validateArray", 0),
  /** `(value, name, min = -2147483648, max = 2147483647)` */
  validateInt32: $newCppFunction("NodeValidator.cpp", "jsFunction_validateInt32", 0),
  /** `(value, name, positive = false)` */
  validateUint32: $newCppFunction("NodeValidator.cpp", "jsFunction_validateUint32", 0),
  /** `(signal, name = 'signal')` */
  validateSignalName: $newCppFunction("NodeValidator.cpp", "jsFunction_validateSignalName", 0),
  /** `(data, encoding)` */
  validateEncoding: $newCppFunction("NodeValidator.cpp", "jsFunction_validateEncoding", 0),
  /** `(value, name)` */
  validatePlainFunction: $newCppFunction("NodeValidator.cpp", "jsFunction_validatePlainFunction", 0),
  /** `(value, name)` */
  validateUndefined,
  /** `(buffer, name = 'buffer')` */
  validateBuffer: $newCppFunction("NodeValidator.cpp", "jsFunction_validateBuffer", 0),
  /** `(value, name, oneOf)` */
  validateOneOf: $newCppFunction("NodeValidator.cpp", "jsFunction_validateOneOf", 0),
  isUint8Array: value => value instanceof Uint8Array,
  /** `(object, fieldKey, className)` */
  validateInternalField,
};
