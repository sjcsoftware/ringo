#!/usr/bin/env python3
"""Sign the packaged release and add it to the GitHub-hosted Sparkle feed."""
import argparse
import datetime
import email.utils
import html
import pathlib
import plistlib
import subprocess
import xml.etree.ElementTree as ET

ROOT = pathlib.Path(__file__).resolve().parent.parent
SPARKLE = "http://www.andymatuschak.org/xml-namespaces/sparkle"
ET.register_namespace("sparkle", SPARKLE)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("dmg", type=pathlib.Path)
    parser.add_argument("--sign-update", type=pathlib.Path,
                        default=ROOT / ".build/artifacts/sparkle/Sparkle/bin/sign_update")
    args = parser.parse_args()
    dmg = args.dmg.resolve()
    with (ROOT / "dist/Ringo.app/Contents/Info.plist").open("rb") as source:
        info = plistlib.load(source)
    version, build = info["CFBundleShortVersionString"], info["CFBundleVersion"]
    if dmg.name != f"Ringo-{version}-arm64.dmg":
        parser.error("Expected the arm64 release DMG matching dist/Ringo.app")
    if not dmg.is_file() or not args.sign_update.is_file():
        parser.error("Build the DMG and resolve Sparkle before signing")
    changelog = (ROOT / "docs/CHANGELOG.md").read_text()
    heading = f"## {version}\n"
    if heading not in changelog:
        parser.error("Add release notes to docs/CHANGELOG.md before signing")
    notes = changelog.split(heading, 1)[1].split("\n## ", 1)[0].strip()

    # The tool reads the key in Keychain; only the public signature is captured.
    signature = subprocess.check_output(
        [str(args.sign_update), "--account", "sjcsoftware.ringo", "-p", str(dmg)], text=True
    ).strip()
    subprocess.run([str(args.sign_update), "--account", "sjcsoftware.ringo", "--verify", str(dmg), signature], check=True)

    feed = ROOT / "appcast.xml"
    tree = ET.parse(feed)
    channel = tree.getroot().find("channel")
    for item in list(channel.findall("item")):
        if item.findtext(f"{{{SPARKLE}}}version") == build:
            parser.error("This build is already in appcast.xml; bump the build before releasing")
    item = ET.Element("item")
    ET.SubElement(item, "title").text = f"Ringo {version}"
    ET.SubElement(item, "pubDate").text = email.utils.format_datetime(datetime.datetime.now(datetime.timezone.utc))
    ET.SubElement(item, f"{{{SPARKLE}}}version").text = build
    ET.SubElement(item, f"{{{SPARKLE}}}shortVersionString").text = version
    ET.SubElement(item, f"{{{SPARKLE}}}minimumSystemVersion").text = info["LSMinimumSystemVersion"]
    ET.SubElement(item, "link").text = f"https://github.com/sjcsoftware/ringo/releases/tag/v{version}"
    ET.SubElement(item, "description").text = "<ul>" + "".join(
        f"<li>{html.escape(line[2:])}</li>" for line in notes.splitlines() if line.startswith("- ")
    ) + "</ul>"
    ET.SubElement(item, "enclosure", {
        "url": f"https://github.com/sjcsoftware/ringo/releases/download/v{version}/{dmg.name}",
        "type": "application/octet-stream", "length": str(dmg.stat().st_size),
        f"{{{SPARKLE}}}edSignature": signature,
    })
    channel.insert(3, item)
    ET.indent(tree, space="  ")
    tree.write(feed, encoding="utf-8", xml_declaration=True)
    print(f"Signed {dmg.name}; updated appcast.xml for {version} (build {build})")


if __name__ == "__main__":
    main()
