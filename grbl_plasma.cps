/**
  Copyright (C) 2012-2019 by Autodesk, Inc.
  All rights reserved.

  Copyright (C) 2020 Jason Greathouse
  All rights reserved.

  $Revision: 24001 00000000000000000000 $
  $Date: 2020-05-24 15:08:57 $

  grbl-plasma post processor configuration.
*/

description = "Grbl Plasma";
vendor = "grbl";
vendorUrl = "https://github.com/jgreat/fusion360-post-grbl-plasma";
legal = "Copyright (C) 2012-2019 by Autodesk, Inc. - Copyright (C) 2020 Jason Greathouse";
certificationLevel = 2;
minimumRevision = 24000;

longDescription = "Generic post for Grbl Plasma cutting.";

extension = "nc";
setCodePage("ascii");

capabilities = CAPABILITY_JET;
tolerance = spatial(0.002, MM);

minimumChordLength = spatial(0.25, MM);
minimumCircularRadius = spatial(0.01, MM);
maximumCircularRadius = spatial(1000, MM);
minimumCircularSweep = toRad(0.01);
maximumCircularSweep = toRad(180);
allowHelicalMoves = true;
allowedCircularPlanes = undefined; // allow any circular motion

// defaults for user-defined properties
properties = {
  writeMachine: true,
  showSequenceNumbers: false,
  sequenceNumberStart: 10,
  sequenceNumberIncrement: 1,
  separateWordsWithSpace: true,
  pierceDelay: 1,
  useZAxis: true,
  pierceHeight: 3.8,
  useG0: true,
  torchOnCommand: "S255 M3",
  torchOffCommand: "S0 M5"
};

// user-defined property definitions
propertyDefinitions = {
  writeMachine: {
    title: "Write machine",
    description: "Output the machine settings in the header of the code.",
    group: 0,
    type: "boolean"
  },
  showSequenceNumbers: {
    title: "Use sequence numbers",
    description: "Use sequence numbers for each block of outputted code.",
    group: 1,
    type: "boolean"
  },
  sequenceNumberStart: {
    title: "Start sequence number",
    description: "The number at which to start the sequence numbers.",
    group: 1,
    type: "integer"
  },
  sequenceNumberIncrement: {
    title: "Sequence number increment",
    description: "The amount by which the sequence number is incremented by in each block.",
    group: 1,
    type: "integer"
  },
  separateWordsWithSpace: {
    title: "Separate words with space",
    description: "Adds spaces between words if 'yes' is selected.",
    group: 1,
    type: "boolean"
  },
  pierceDelay: {
    title: "Pierce Delay",
    description: "Specifies the delay to pierce in seconds.",
    type: "number"
  },
  pierceHeight: {
    title: "Pierce Height",
    description: "Specifies the pierce height.",
    type: "number"
  },
  useZAxis: {
    title: "Use Z axis",
    description: "Specifies to enable the output for Z coordinates.",
    type: "boolean"
  },
  useG0: {
    title: "Use G0",
    description: "Toggle between using G0 or G1 with a high Feedrate for rapid movements.",
    type: "boolean"
  },
  torchOnCommand: {
    title: "Torch On Command",
    description: "G-code Command to turn the torch on. This may vary depending on what pins your torch relay is connected to.",
    type: "string"
  },
  torchOffCommand: {
    title: "Torch Off Command",
    description: "G-code Command to turn the torch on. This may vary depending on what pins your torch relay is connected to.",
    type: "string"
  }
};

var gFormat = createFormat({prefix:"G", decimals:0});
var mFormat = createFormat({prefix:"M", decimals:0});

var xyzFormat = createFormat({decimals:(unit == MM ? 3 : 4), forceDecimal:true});
var zFormat = createFormat({decimals:(unit == MM ? 3 : 4), forceDecimal:true});
var feedFormat = createFormat({decimals:(unit == MM ? 1 : 2), forceDecimal:true});
var toolFormat = createFormat({decimals:0});
var powerFormat = createFormat({decimals:0});
var secFormat = createFormat({decimals:3, forceDecimal:true}); // seconds - range 0.001-1000

var xOutput = createVariable({prefix:"X"}, xyzFormat);
var yOutput = createVariable({prefix:"Y"}, xyzFormat);
var zOutput = createVariable({prefix:"Z"}, xyzFormat);
var feedOutput = createVariable({prefix:"F"}, feedFormat);
var sOutput = createVariable({prefix:"S", force:true}, powerFormat);

// circular output
var iOutput = createVariable({prefix:"I", force: true}, xyzFormat);
var jOutput = createVariable({prefix:"J", force: true}, xyzFormat);

var gMotionModal = createModal({force:true}, gFormat); // modal group 1 // G0-G3, ...
var gPlaneModal = createModal({onchange:function () {gMotionModal.reset();}}, gFormat); // modal group 2 // G17-19
var gAbsIncModal = createModal({}, gFormat); // modal group 3 // G90-91
var gFeedModeModal = createModal({}, gFormat); // modal group 5 // G93-94
var gUnitModal = createModal({}, gFormat); // modal group 6 // G20-21

var WARNING_WORK_OFFSET = 0;

var pendingRadiusCompensation = -1;
var powerIsOn = false;

// collected state
var sequenceNumber;
var currentWorkOffset;

/**
  Writes the specified block.
*/
function writeBlock() {
  if (properties.showSequenceNumbers) {
    writeWords2("N" + sequenceNumber, arguments);
    sequenceNumber += properties.sequenceNumberIncrement;
  } else {
    writeWords(arguments);
  }
}

function formatComment(text) {
  return "(" + String(text).replace(/[()]/g, "") + ")";
}

/**
  Output a comment.
*/
function writeComment(text) {
  writeln(formatComment(text));
}

function onOpen() {
  if (properties.useZAxis) {
    zFormat.setOffset(properties.pierceHeight);
    zOutput = createVariable({prefix:"Z"}, zFormat);
  } else {
    zOutput.disable();
  }

  if (!properties.separateWordsWithSpace) {
    setWordSeparator("");
  }

  sequenceNumber = properties.sequenceNumberStart;
  writeln("%");

  if (programName) {
    writeComment(programName);
  }
  if (programComment) {
    writeComment(programComment);
  }

  // dump machine configuration
  var vendor = machineConfiguration.getVendor();
  var model = machineConfiguration.getModel();
  var description = machineConfiguration.getDescription();

  if (properties.writeMachine && (vendor || model || description)) {
    writeComment(localize("Machine"));
    if (vendor) {
      writeComment("  " + localize("vendor") + ": " + vendor);
    }
    if (model) {
      writeComment("  " + localize("model") + ": " + model);
    }
    if (description) {
      writeComment("  " + localize("description") + ": "  + description);
    }
  }

  if ((getNumberOfSections() > 0) && (getSection(0).workOffset == 0)) {
    for (var i = 0; i < getNumberOfSections(); ++i) {
      if (getSection(i).workOffset > 0) {
        error(localize("Using multiple work offsets is not possible if the initial work offset is 0."));
        return;
      }
    }
  }

  // absolute coordinates and feed per min
  writeBlock(gAbsIncModal.format(90), gFeedModeModal.format(94));
  writeBlock(gPlaneModal.format(17));

  switch (unit) {
  case IN:
    writeBlock(gUnitModal.format(20));
    break;
  case MM:
    writeBlock(gUnitModal.format(21));
    break;
  }

}

function onComment(message) {
  writeComment(message);
}

/** Force output of X, Y, and Z. */
function forceXYZ() {
  xOutput.reset();
  yOutput.reset();
  zOutput.reset();
}

/** Force output of X, Y, Z, and F on next output. */
function forceAny() {
  forceXYZ();
  feedOutput.reset();
}

function onSection() {

  writeln("");
  
  if (hasParameter("operation-comment")) {
    var comment = getParameter("operation-comment");
    if (comment) {
      writeComment(comment);
    }
  }
  
  switch (tool.type) {
    case TOOL_PLASMA_CUTTER:
      break;
    default:
      error(localize("The CNC does not support the required tool/process. Only plasma cutting is supported."));
      return;
  }

  switch (currentSection.jetMode) {
    case JET_MODE_THROUGH:
      break;
    case JET_MODE_ETCHING:
      error(localize("Etch cutting mode is not supported."));
      break;
    case JET_MODE_VAPORIZE:
      error(localize("Vaporize cutting mode is not supported."));
      break;
    default:
      error(localize("Unsupported cutting mode."));
      return;
  }

  // wcs
  var workOffset = currentSection.workOffset;
  if (workOffset == 0) {
    warningOnce(localize("Work offset has not been specified. Using G54 as WCS."), WARNING_WORK_OFFSET);
    workOffset = 1;
  }
  if (workOffset > 0) {
    if (workOffset > 6) {
      error(localize("Work offset out of range."));
      return;
    } else {
      if (workOffset != currentWorkOffset) {
        writeBlock(gFormat.format(53 + workOffset)); // G54->G59
        currentWorkOffset = workOffset;
      }
    }
  }

  { // pure 3D
    var remaining = currentSection.workPlane;
    if (!isSameDirection(remaining.forward, new Vector(0, 0, 1))) {
      error(localize("Tool orientation is not supported."));
      return;
    }
    setRotation(remaining);
  }
  
  forceAny();
  
  var initialPosition = getFramePosition(currentSection.getInitialPosition());
  var zIsOutput = false;

  if (properties.useZAxis) {
    var previousFinalPosition = isFirstSection() ? initialPosition : getFramePosition(getPreviousSection().getFinalPosition());
    if (xyzFormat.getResultingValue(previousFinalPosition.z) <= xyzFormat.getResultingValue(initialPosition.z)) {
      if (properties.useG0) {
        writeBlock(gMotionModal.format(0), zOutput.format(initialPosition.z));
      } else {
        writeBlock(gMotionModal.format(1), zOutput.format(initialPosition.z), feedOutput.format(highFeedrate));
      }
      zIsOutput = true;
    }
  }

  if (properties.useG0) {
    writeBlock(gMotionModal.format(0), xOutput.format(initialPosition.x), yOutput.format(initialPosition.y));
  } else {
    writeBlock(gMotionModal.format(1), xOutput.format(initialPosition.x), yOutput.format(initialPosition.y), feedOutput.format(highFeedrate));
  }
  initialG31 = true;
  writeG31();

  if (properties.useZAxis && !zIsOutput) {
    if (properties.useG0) {
      writeBlock(gMotionModal.format(0), zOutput.format(initialPosition.z));
    } else {
      writeBlock(gMotionModal.format(1), zOutput.format(initialPosition.z), feedOutput.format(highFeedrate));
    }
  }
}

function onDwell(seconds) {
  if (seconds > 99999.999) {
    warning(localize("Dwelling time is out of range."));
  }
  seconds = clamp(0.001, seconds, 99999.999);
  writeBlock(gFormat.format(4), "P" + secFormat.format(seconds));
}

function writeG31() {}

function onRadiusCompensation() {
  pendingRadiusCompensation = radiusCompensation;
}


function onPower(power) {
  initialG31 = false;
  if (power) {
    writeBlock(properties.torchOnCommand);
  } else {
    writeBlock(properties.torchOffCommand);
  }
  powerIsOn = power;
  if (power) {
    onDwell(properties.pierceDelay);
    if (zFormat.isSignificant(properties.pierceHeight)) {
      feedOutput.reset();
      var f = (hasParameter("operation:tool_feedEntry") ? getParameter("operation:tool_feedEntry") : toPreciseUnit(1000, MM));
      zFormat.setOffset(0);
      zOutput = createVariable({prefix:"Z"}, zFormat);
      writeBlock(gMotionModal.format(1), zOutput.format(getCurrentPosition().z), feedOutput.format(f));
    }
  } else {
    if (zFormat.isSignificant(properties.pierceHeight)) {
      zFormat.setOffset(properties.pierceHeight);
      zOutput = createVariable({prefix:"Z"}, zFormat);
    }
    writeln("");
  }
}

function onRapid(_x, _y, _z) {
  var x = xOutput.format(_x);
  var y = yOutput.format(_y);
  var z = zOutput.format(_z);
  if (x || y || z) {
    if (pendingRadiusCompensation >= 0) {
      error(localize("Radius compensation mode cannot be changed at rapid traversal."));
      return;
    }
    if (properties.useG0) {
      writeBlock(gMotionModal.format(0), x, y, z);
    } else {
      writeBlock(gMotionModal.format(1), x, y, z, feedOutput.format(highFeedrate));
    }
    feedOutput.reset();
  }
}

function onLinear(_x, _y, _z, feed) {
  // at least one axis is required
  if (pendingRadiusCompensation >= 0) {
    // ensure that we end at desired position when compensation is turned off
    xOutput.reset();
    yOutput.reset();
  }
  var x = xOutput.format(_x);
  var y = yOutput.format(_y);
  var z = zOutput.format(_z);
  var f = feedOutput.format(feed);

  if (x || y || (z && !powerIsOn)) {
    if (pendingRadiusCompensation >= 0) {
      error(localize("Radius compensation mode is not supported."));
      return;
    } else {
      writeBlock(gMotionModal.format(1), x, y, z, f);
    }
  }
}

function onRapid5D(_x, _y, _z, _a, _b, _c) {
  error(localize("The CNC does not support 5-axis simultaneous toolpath."));
}

function onLinear5D(_x, _y, _z, _a, _b, _c, feed) {
  error(localize("The CNC does not support 5-axis simultaneous toolpath."));
}

function forceCircular(plane) {
  switch (plane) {
  case PLANE_XY:
    xOutput.reset();
    yOutput.reset();
    iOutput.reset();
    jOutput.reset();
    break;
  case PLANE_ZX:
    zOutput.reset();
    xOutput.reset();
    kOutput.reset();
    iOutput.reset();
    break;
  case PLANE_YZ:
    yOutput.reset();
    zOutput.reset();
    jOutput.reset();
    kOutput.reset();
    break;
  }
}

function onCircular(clockwise, cx, cy, cz, x, y, z, feed) {
  if (pendingRadiusCompensation >= 0) {
    error(localize("Radius compensation cannot be activated/deactivated for a circular move."));
    return;
  }

  var start = getCurrentPosition();

  if (isFullCircle()) {
    if (isHelical()) {
      linearize(tolerance);
      return;
    }
    switch (getCircularPlane()) {
    case PLANE_XY:
      forceCircular(getCircularPlane());
      writeBlock(gMotionModal.format(clockwise ? 2 : 3), xOutput.format(x), yOutput.format(y),  iOutput.format(cx - start.x), jOutput.format(cy - start.y), feedOutput.format(feed));
      break;
    default:
      linearize(tolerance);
    }
  } else {
    switch (getCircularPlane()) {
    case PLANE_XY:
      forceCircular(getCircularPlane());
      writeBlock(gMotionModal.format(clockwise ? 2 : 3), xOutput.format(x), yOutput.format(y), iOutput.format(cx - start.x), jOutput.format(cy - start.y), feedOutput.format(feed));
      break;
    default:
      linearize(tolerance);
    }
  }
}

var mapCommand = {
  COMMAND_STOP:0,
  COMMAND_END:2,
};

function onCommand(command) {
  switch (command) {
  case COMMAND_POWER_ON:
    return;
  case COMMAND_POWER_OFF:
    return;
  case COMMAND_LOCK_MULTI_AXIS:
    return;
  case COMMAND_UNLOCK_MULTI_AXIS:
    return;
  case COMMAND_BREAK_CONTROL:
    return;
  case COMMAND_TOOL_MEASURE:
    return;
  }

  var stringId = getCommandStringId(command);
  var mcode = mapCommand[stringId];
  if (mcode != undefined) {
    writeBlock(mFormat.format(mcode));
  } else {
    onUnsupportedCommand(command);
  }
}

function onSectionEnd() {
  forceAny();
}

function onClose() {
  writeBlock(gMotionModal.format(1), sOutput.format(0)); // plasma off
  writeBlock(mFormat.format(30)); // stop program, spindle stop, coolant off
  writeln("%");
}
