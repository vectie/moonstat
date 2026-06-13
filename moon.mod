name = "vectie/moonstat"

version = "0.1.0"

readme = "README.mbt.md"

repository = ""

license = "Apache-2.0"

keywords = [ ]

description = "Anthropic to OpenAI Codex OAuth Gateway"

import {
  "moonbitlang/async@0.16.6",
  "moonbitlang/x@0.4.40",
  "moonbitlang/regexp@0.3.5",
}

preferred_target = "native"

options(
  bin: "moonstat",
)