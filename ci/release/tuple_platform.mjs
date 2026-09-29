import fs from 'node:fs';
import path from 'node:path';

function platformFailure(code, platform, actual) {
  console.error(`${code} expected=${platform} actual=${actual}`);
  process.exit(65);
}

export function selectTuplePin(pins, platform) {
  const pin = pins.version === 2 && pins.platforms?.[platform];
  if (!pin) platformFailure('BOOTSTRAP_TUPLE_PLATFORM_PIN_MISSING', platform, platform);
  if (pin.platform !== platform) platformFailure('BOOTSTRAP_TUPLE_PLATFORM_MISMATCH', platform, pin.platform);
  return pin;
}

export function verifyTuplePlatform(tuple, platform) {
  const platforms = fs.readFileSync(path.join(tuple, 'MANIFEST'), 'utf8')
    .split('\n').filter(line => line.startsWith('PLATFORM=')).map(line => line.slice(9));
  if (platforms.length !== 1 || platforms[0] !== platform) {
    platformFailure('BOOTSTRAP_TUPLE_PLATFORM_MISMATCH', platform, platforms.join(','));
  }
}
