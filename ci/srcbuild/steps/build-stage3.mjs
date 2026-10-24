#!/usr/bin/env zx
import {prepareBootstrapEnvironment} from '../../bootstrap/prepare-bootstrap-plans.mjs';
import {bootstrap} from '../../bootstrap/bootstrap.mjs';
const {config}=await prepareBootstrapEnvironment();
await bootstrap({config,stage:'all',from:process.env.CJCJ_SDK_FROM||'stage3-std',packageOutput:false});
