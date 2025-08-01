import { expect, test } from "bun:test";
import { chmodSync } from "fs";
import { bunEnv, isWindows, tempDirWithFiles } from "harness";
import path from "path";

test.skipIf(isWindows)("spawn uses PATH from env if present", async () => {
  const tmpDir = await tempDirWithFiles("spawn-path", {
    "test-script": `#!/usr/bin/env bash
echo "hello from script"`,
  });

  chmodSync(path.join(tmpDir, "test-script"), 0o777);

  const proc = Bun.spawn(["test-script"], {
    env: {
      ...bunEnv,
      PATH: tmpDir + ":" + bunEnv.PATH,
    },
  });

  const output = await proc.stdout.text();
  expect(output.trim()).toBe("hello from script");

  const status = await proc.exited;
  expect(status).toBe(0);
});
