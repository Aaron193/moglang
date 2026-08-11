"use strict";

const SUPPORTED_PROTOCOL = { min: 1, max: 1 };

function protocolMetadata(initializeResult) {
  const result = initializeResult || {};
  const capabilities = result.capabilities || {};
  const experimental = capabilities.experimental || {};
  const mog = result.mog || experimental.mog || experimental.mogTooling || {};
  const raw = mog.toolingProtocolVersion ?? mog.protocolVersion ?? result.toolingProtocolVersion;
  const version = typeof raw === "string" ? Number.parseInt(raw.split(".")[0], 10) : raw;
  return {
    serverVersion: result.serverInfo && result.serverInfo.version,
    protocolVersion: Number.isInteger(version) ? version : null,
    features: Array.isArray(mog.features) ? mog.features : []
  };
}

function checkCompatibility(initializeResult, supported = SUPPORTED_PROTOCOL) {
  const metadata = protocolMetadata(initializeResult);
  if (metadata.protocolVersion === null) {
    return {
      compatible: false,
      legacy: true,
      reason: "server did not advertise a tooling protocol version and is too old for this extension",
      ...metadata
    };
  }
  const compatible =
    metadata.protocolVersion >= supported.min && metadata.protocolVersion <= supported.max;
  return {
    compatible,
    legacy: false,
    reason: compatible
      ? null
      : `server tooling protocol ${metadata.protocolVersion} is outside the supported range ${supported.min}-${supported.max}`,
    ...metadata
  };
}

module.exports = { SUPPORTED_PROTOCOL, checkCompatibility, protocolMetadata };
