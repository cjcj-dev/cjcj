#!/usr/bin/env zx
import fs from 'node:fs/promises';
import path from 'node:path';
import {selectJdk} from './build-java-interop.mjs';
import {command} from './sdk-flow.mjs';

// The JVM assertion needs a Cangjie-generated Java class, both Java runtime
// modules and the packaged loader jar; a compiler-only probe misses that edge.
export async function verifyInstalledJava(sdk,work) {
  const {home}=await selectJdk();
  await fs.mkdir(work,{recursive:true});
  const cwd=await fs.mkdtemp(path.join(work,'java-'));
  await fs.mkdir(path.join(cwd,'src'));await fs.mkdir(path.join(cwd,'generated'));
  await fs.writeFile(path.join(cwd,'src/probe.cj'),`package sdkprobe
import java.lang.*
@Java["check.Base"]
public open foreign class Base {
    public init()
    public static func Record(s: JString): Unit
}
@Java
public class Probe <: Base {
    public init(active: Bool) {
        if (active) { Record(JString("sdk-java")) }
    }
}
`);
  await fs.writeFile(path.join(cwd,'Base.java'),`package check;
public class Base {
    static String result;
    public static void Record(String s) { result = s; }
    public static void main(String[] args) {
        new sdkprobe.Probe(true);
        if (!"sdk-java".equals(result)) throw new AssertionError(result);
    }
}
`);
  const runtime=path.join(sdk,'runtime/lib/linux_x86_64_cjnative'),cp='.'+path.delimiter+path.join(sdk,'lib/library-loader.jar');
  const env={CANGJIE_HOME:sdk,JAVA_HOME:home,LD_LIBRARY_PATH:[cwd,runtime,path.join(sdk,'lib/linux_x86_64_cjnative')].join(path.delimiter)};
  for(const argv of [[path.join(sdk,'bin/cjc'),'--output-type=dylib','-p','src','-L'+runtime,'-ljava.internal','-ljava.lang','--output-javagen-dir=generated'],
    [path.join(home,'bin/javac'),'-cp',cp,'Base.java','generated/Probe.java','-d','.'],
    [path.join(home,'bin/java'),'-cp',cp,'-Djava.library.path='+cwd,'check.Base']])await command(argv,{cwd,env});
}
