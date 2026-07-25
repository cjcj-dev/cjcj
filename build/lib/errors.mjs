// Port of cangjie-build/src/cangjie_build/errors.py.

export class BuildError extends Error {
  constructor(stage, message, {exitCode} = {}) {
    const suffix = exitCode === undefined ? '' : ` (exit=${exitCode})`;
    super(`[${stage}] ${message}${suffix}`);
    this.name = 'BuildError';
    this.stage = stage;
    this.exitCode = exitCode;
  }
}

export class ConfigError extends Error {
  constructor(message) {
    super(message);
    this.name = 'ConfigError';
  }
}
