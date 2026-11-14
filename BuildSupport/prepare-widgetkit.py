#!/usr/bin/env python3
"""Expose the system's existing blur preference in a locally generated SDK module."""

import os
from pathlib import Path
import subprocess


project = Path(__file__).resolve().parent.parent
sdk = Path(os.environ.get("SDKROOT") or subprocess.check_output(
    ["xcrun", "--sdk", "macosx", "--show-sdk-path"], text=True
).strip())
interfaces = sdk / "System/Library/Frameworks/WidgetKit.framework/Modules/WidgetKit.swiftmodule"
destination = project / "build/WidgetKitCompatibility/WidgetKit.swiftmodule"
destination.mkdir(parents=True, exist_ok=True)

declarations = """
// These declarations resolve to WidgetKit's existing implementation.
// Apple Batteries uses preferredBackgroundStyle(.blur) for its host background.
@available(macOS 14.0, *)
public enum WidgetBackgroundStyle {
  case blur
}
@available(macOS 14.0, *)
extension SwiftUI.WidgetConfiguration {
  @_Concurrency.MainActor @preconcurrency public func preferredBackgroundStyle(_ style: WidgetKit.WidgetBackgroundStyle) -> some SwiftUI.WidgetConfiguration
}
"""

for architecture in ("arm64", "arm64e", "x86_64"):
    source_architecture = "arm64e" if architecture == "arm64" else architecture
    source = interfaces / f"{source_architecture}-apple-macos.swiftinterface"
    text = source.read_text()
    if "func preferredBackgroundStyle(" not in text:
        text += declarations
    output = destination / f"{architecture}-apple-macos.swiftinterface"
    if not output.exists() or output.read_text() != text:
        output.write_text(text)
