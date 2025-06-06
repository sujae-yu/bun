"use strict";

const { inspect } = require("internal/util/inspect");
const colors = require("internal/util/colors");
const { validateObject } = require("internal/validators");
const { myersDiff, printMyersDiff, printSimpleMyersDiff } = require("internal/assert/myers_diff") as typeof Internal;

const ErrorCaptureStackTrace = Error.captureStackTrace;
const ObjectAssign = Object.assign;
const ObjectDefineProperty = Object.defineProperty;
const ObjectGetPrototypeOf = Object.getPrototypeOf;
const ObjectPrototypeHasOwnProperty = Object.prototype.hasOwnProperty;
const ArrayPrototypeJoin = Array.prototype.join;
const ArrayPrototypePop = Array.prototype.pop;
const ArrayPrototypeSlice = Array.prototype.slice;
const StringPrototypeRepeat = String.prototype.repeat;
const StringPrototypeSlice = String.prototype.slice;
const StringPrototypeSplit = String.prototype.split;

declare namespace Internal {
  const enum Operation {
    Insert = 0,
    Delete = 1,
    Equal = 2,
  }
  interface Diff {
    kind: Operation;
    value: string;
  }

  function myersDiff(actual: string, expected: string, checkCommaDisparity?: boolean, lines?: boolean): string;
  // todo

  function printMyersDiff(...args: any[]): any;
  function printSimpleMyersDiff(...args: any[]): any;
}

const kReadableOperator = {
  deepStrictEqual: "Expected values to be strictly deep-equal:",
  strictEqual: "Expected values to be strictly equal:",
  strictEqualObject: 'Expected "actual" to be reference-equal to "expected":',
  deepEqual: "Expected values to be loosely deep-equal:",
  notDeepStrictEqual: 'Expected "actual" not to be strictly deep-equal to:',
  notStrictEqual: 'Expected "actual" to be strictly unequal to:',
  notStrictEqualObject: 'Expected "actual" not to be reference-equal to "expected":',
  notDeepEqual: 'Expected "actual" not to be loosely deep-equal to:',
  notIdentical: "Values have same structure but are not reference-equal:",
  notDeepEqualUnequal: "Expected values not to be loosely deep-equal:",
};

const kMaxShortStringLength = 12;
const kMaxLongStringLength = 512;

function copyError(source) {
  const target = ObjectAssign({ __proto__: ObjectGetPrototypeOf(source) }, source);
  ObjectDefineProperty(target, "message", {
    __proto__: null,
    value: source.message,
  });
  if (ObjectPrototypeHasOwnProperty.$call(source, "cause")) {
    let { cause } = source;

    if (Error.isError(cause)) {
      cause = copyError(cause);
    }

    ObjectDefineProperty(target, "cause", { __proto__: null, value: cause });
  }
  return target;
}

function inspectValue(val) {
  // The util.inspect default values could be changed. This makes sure the
  // error messages contain the necessary information nevertheless.
  return inspect(val, {
    compact: false,
    customInspect: false,
    depth: 1000,
    maxArrayLength: Infinity,
    // Assert compares only enumerable properties (with a few exceptions).
    showHidden: false,
    // Assert does not detect proxies currently.
    showProxy: false,
    sorted: true,
    // Inspect getters as we also check them when comparing entries.
    getters: true,
  });
}

function getErrorMessage(operator, message) {
  return message || kReadableOperator[operator];
}

function checkOperator(actual, expected, operator) {
  // In case both values are objects or functions explicitly mark them as not
  // reference equal for the `strictEqual` operator.
  if (
    operator === "strictEqual" &&
    ((typeof actual === "object" && actual !== null && typeof expected === "object" && expected !== null) ||
      (typeof actual === "function" && typeof expected === "function"))
  ) {
    operator = "strictEqualObject";
  }

  return operator;
}

function getColoredMyersDiff(actual, expected) {
  const header = `${colors.green}actual${colors.white} ${colors.red}expected${colors.white}`;
  const skipped = false;

  // const diff = myersDiff(StringPrototypeSplit.$call(actual, ""), StringPrototypeSplit.$call(expected, ""));
  const diff = myersDiff(actual, expected, false, false);
  let message = printSimpleMyersDiff(diff);

  if (skipped) {
    message += "...";
  }

  return { message, header, skipped };
}

function getStackedDiff(actual, expected) {
  const isStringComparison = typeof actual === "string" && typeof expected === "string";

  let message = `\n${colors.green}+${colors.white} ${actual}\n${colors.red}- ${colors.white}${expected}`;
  const stringsLen = actual.length + expected.length;
  const maxTerminalLength = process.stderr.isTTY ? process.stderr.columns : 80;
  const showIndicator = isStringComparison && stringsLen <= maxTerminalLength;

  if (showIndicator) {
    let indicatorIdx = -1;

    for (let i = 0; i < actual.length; i++) {
      if (actual[i] !== expected[i]) {
        // Skip the indicator for the first 2 characters because the diff is immediately apparent
        // It is 3 instead of 2 to account for the quotes
        if (i >= 3) {
          indicatorIdx = i;
        }
        break;
      }
    }

    if (indicatorIdx !== -1) {
      message += `\n${StringPrototypeRepeat.$call(" ", indicatorIdx + 2)}^`;
    }
  }

  return { message };
}

function getSimpleDiff(originalActual, actual: string, originalExpected, expected: string) {
  let stringsLen = actual.length + expected.length;
  // Accounting for the quotes wrapping strings
  if (typeof originalActual === "string") {
    stringsLen -= 2;
  }
  if (typeof originalExpected === "string") {
    stringsLen -= 2;
  }
  if (stringsLen <= kMaxShortStringLength && (originalActual !== 0 || originalExpected !== 0)) {
    return { message: `${actual} !== ${expected}`, header: "" };
  }

  const isStringComparison = typeof originalActual === "string" && typeof originalExpected === "string";
  // colored myers diff
  if (isStringComparison && colors.hasColors) {
    return getColoredMyersDiff(actual, expected);
  }

  return getStackedDiff(actual, expected);
}

function isSimpleDiff(actual, inspectedActual, expected, inspectedExpected) {
  if (inspectedActual.length > 1 || inspectedExpected.length > 1) {
    return false;
  }

  return typeof actual !== "object" || actual === null || typeof expected !== "object" || expected === null;
}

function createErrDiff(actual, expected, operator, customMessage) {
  operator = checkOperator(actual, expected, operator);

  let skipped = false;
  let message = "";
  const inspectedActual = inspectValue(actual);
  const inspectedExpected = inspectValue(expected);
  const inspectedSplitActual = StringPrototypeSplit.$call(inspectedActual, "\n");
  const inspectedSplitExpected = StringPrototypeSplit.$call(inspectedExpected, "\n");
  const showSimpleDiff = isSimpleDiff(actual, inspectedSplitActual, expected, inspectedSplitExpected);
  let header = `${colors.green}+ actual${colors.white} ${colors.red}- expected${colors.white}`;

  if (showSimpleDiff) {
    const simpleDiff = getSimpleDiff(actual, inspectedSplitActual[0], expected, inspectedSplitExpected[0]);
    message = simpleDiff.message;
    if (typeof simpleDiff.header !== "undefined") {
      header = simpleDiff.header;
    }
    if (simpleDiff.skipped) {
      skipped = true;
    }
  } else if (inspectedActual === inspectedExpected) {
    // Handles the case where the objects are structurally the same but different references
    operator = "notIdentical";
    if (inspectedSplitActual.length > 50) {
      message = `${ArrayPrototypeJoin.$call(ArrayPrototypeSlice.$call(inspectedSplitActual, 0, 50), "\n")}\n...}`;
      skipped = true;
    } else {
      message = ArrayPrototypeJoin.$call(inspectedSplitActual, "\n");
    }
    header = "";
  } else {
    const checkCommaDisparity = actual != null && typeof actual === "object";
    const diff = myersDiff(inspectedActual, inspectedExpected, checkCommaDisparity, true);

    const myersDiffMessage = printMyersDiff(diff);
    message = myersDiffMessage.message;

    if (myersDiffMessage.skipped) {
      skipped = true;
    }
  }

  const headerMessage = `${getErrorMessage(operator, customMessage)}\n${header}`;
  const skippedMessage = skipped ? "\n... Skipped lines" : "";

  return `${headerMessage}${skippedMessage}\n${message}\n`;
}

function addEllipsis(string) {
  const lines = StringPrototypeSplit.$call(string, "\n", 11);
  if (lines.length > 10) {
    lines.length = 10;
    return `${ArrayPrototypeJoin.$call(lines, "\n")}\n...`;
  } else if (string.length > kMaxLongStringLength) {
    return `${StringPrototypeSlice.$call(string, kMaxLongStringLength)}...`;
  }
  return string;
}

class AssertionError extends Error {
  generatedMessage;
  actual;
  expected;
  operator;

  constructor(options) {
    validateObject(options, "options");
    const {
      message,
      operator,
      stackStartFn,
      details,
      // Compatibility with older versions.
      stackStartFunction,
    } = options;
    let { actual, expected } = options;

    // NOTE: stack trace is always writable.
    const limit = Error.stackTraceLimit;
    Error.stackTraceLimit = 0;

    if (message != null) {
      if (operator === "deepStrictEqual" || operator === "strictEqual") {
        super(createErrDiff(actual, expected, operator, message));
      } else {
        super(String(message));
      }
    } else {
      // Reset colors on each call to make sure we handle dynamically set environment
      // variables correct.
      colors.refresh();
      // Prevent the error stack from being visible by duplicating the error
      // in a very close way to the original in case both sides are actually
      // instances of Error.
      if (
        typeof actual === "object" &&
        actual !== null &&
        typeof expected === "object" &&
        expected !== null &&
        "stack" in actual &&
        actual instanceof Error &&
        "stack" in expected &&
        expected instanceof Error
      ) {
        actual = copyError(actual);
        expected = copyError(expected);
      }

      if (operator === "deepStrictEqual" || operator === "strictEqual") {
        super(createErrDiff(actual, expected, operator, message));
      } else if (operator === "notDeepStrictEqual" || operator === "notStrictEqual") {
        // In case the objects are equal but the operator requires unequal, show
        // the first object and say A equals B
        let base = kReadableOperator[operator];
        const res = StringPrototypeSplit.$call(inspectValue(actual), "\n");

        // In case "actual" is an object or a function, it should not be
        // reference equal.
        if (
          operator === "notStrictEqual" &&
          ((typeof actual === "object" && actual !== null) || typeof actual === "function")
        ) {
          base = kReadableOperator.notStrictEqualObject;
        }

        // Only remove lines in case it makes sense to collapse those.
        // TODO: Accept env to always show the full error.
        if (res.length > 50) {
          res[46] = `${colors.blue}...${colors.white}`;
          while (res.length > 47) {
            ArrayPrototypePop.$call(res);
          }
        }

        // Only print a single input.
        if (res.length === 1) {
          super(`${base}${res[0].length > 5 ? "\n\n" : " "}${res[0]}`);
        } else {
          super(`${base}\n\n${ArrayPrototypeJoin.$call(res, "\n")}\n`);
        }
      } else {
        let res = inspectValue(actual);
        let other = inspectValue(expected);
        const knownOperator = kReadableOperator[operator];
        if (operator === "notDeepEqual" && res === other) {
          res = `${knownOperator}\n\n${res}`;
          if (res.length > 1024) {
            res = `${StringPrototypeSlice.$call(res, 0, 1021)}...`;
          }
          super(res);
        } else {
          if (res.length > kMaxLongStringLength) {
            res = `${StringPrototypeSlice.$call(res, 0, 509)}...`;
          }
          if (other.length > kMaxLongStringLength) {
            other = `${StringPrototypeSlice.$call(other, 0, 509)}...`;
          }
          if (operator === "deepEqual") {
            res = `${knownOperator}\n\n${res}\n\nshould loosely deep-equal\n\n`;
          } else {
            const newOp = kReadableOperator[`${operator}Unequal`];
            if (newOp) {
              res = `${newOp}\n\n${res}\n\nshould not loosely deep-equal\n\n`;
            } else {
              other = ` ${operator} ${other}`;
            }
          }
          super(`${res}${other}`);
        }
      }
    }

    Error.stackTraceLimit = limit;

    this.generatedMessage = !message;
    ObjectDefineProperty(this, "name", {
      __proto__: null,
      value: "AssertionError [ERR_ASSERTION]",
      enumerable: false,
      writable: true,
      configurable: true,
    });
    this.code = "ERR_ASSERTION";
    if (details) {
      for (let i = 0; i < details.length; i++) {
        this["message " + i] = details[i].message;
        this["actual " + i] = details[i].actual;
        this["expected " + i] = details[i].expected;
        this["operator " + i] = details[i].operator;
        this["stack trace " + i] = details[i].stack;
      }
    } else {
      this.actual = actual;
      this.expected = expected;
      this.operator = operator;
    }
    ErrorCaptureStackTrace(this, stackStartFn || stackStartFunction);
    // JSC::Interpreter::getStackTrace() sometimes short-circuits without creating a .stack property.
    // e.g.: https://github.com/oven-sh/WebKit/blob/e32c6356625cfacebff0c61d182f759abf6f508a/Source/JavaScriptCore/interpreter/Interpreter.cpp#L501
    if ($isUndefinedOrNull(this.stack)) {
      ErrorCaptureStackTrace(this, AssertionError);
    }
    // Create error message including the error code in the name.
    this.stack; // eslint-disable-line no-unused-expressions
    // Reset the name.
    this.name = "AssertionError";
  }

  toString() {
    return `${this.name} [${this.code}]: ${this.message}`;
  }

  [inspect.custom](recurseTimes, ctx) {
    // Long strings should not be fully inspected.
    const tmpActual = this.actual;
    const tmpExpected = this.expected;

    if (typeof this.actual === "string") {
      this.actual = addEllipsis(this.actual);
    }
    if (typeof this.expected === "string") {
      this.expected = addEllipsis(this.expected);
    }

    // This limits the `actual` and `expected` property default inspection to
    // the minimum depth. Otherwise those values would be too verbose compared
    // to the actual error message which contains a combined view of these two
    // input values.
    const result = inspect(this, {
      ...ctx,
      customInspect: false,
      depth: 0,
    });

    // Reset the properties after inspection.
    this.actual = tmpActual;
    this.expected = tmpExpected;

    return result;
  }
}

export default AssertionError;
