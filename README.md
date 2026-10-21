# PowerPointLabsLives
PowerPointLabs - created by students at the National University of Singapore - new installer
Home Page: https://www.comp.nus.edu.sg/~pptlabs/

The typical PowerPoint presentation isn't very interesting. Walls of text or bullet points, with few visuals - it's no wonder audiences find it hard to pay attention.

Your slides don't have to be this way, and it doesn't take a whole lot of effort to make them better.

PowerPointLabs is an open source project based in the National University of Singapore. It makes creating engaging PowerPoint presentations easy.

Fancy animations, simplified - Animation Lab makes multi-step multi-object custom animations a breeze.

Zoom and pan with ease - Easily zoom in on and pan between parts of your slides with Zoom Lab.

Narrate your speaker notes - Narrations Lab creates audio explanations from your speaker notes - perfect for self-learning materials.

Caption with a click - Want subtitles with your narration? Captions Lab makes it a one-click process.

Point-by-point highlights - Highlight individual bullet points to show what you're describing with Highlight Lab.

Special effects without special software - Draw attention to a part of the slide with a spotlight or blurring out the rest. Effects Lab has you covered.

Tweak positions to match your layout - Use Positions Lab to perfectly position shapes to create the exact layout you want.

Resize with precision - Resize shapes to match other shapes or to the size you want using Resize Lab.

Match colors, perfectly - Colors Lab makes picking colors a snap, even from outside PowerPoint.

Sync just the styles you want - Sync Lab can copy selected styles from one object to other objects.

Save the shapes, and your effort - Add shapes or other elements to Shapes Lab, and reuse them easily in any presentation.

Cut out custom shapes - Need just part of an image? Crop Lab lets you cut it in the exact shape you want, no image editor necessary.

Paste with more control - Replace an image while preserving its animations. Paste Lab provides many different new ways for you to paste objects in slides.

Add timers to guide in-presentation activities - Want your audience to do an activity for 10 seconds? Timer Lab lets you create visual timers for your slides.

Create roadmaps for long presentations - Need a roadmap for your presentation? Agenda Lab builds one with a single click.

Create picture slides the easy way - No more long hours of tweaking picture slides. With Picture Slides Lab, all you need to do is compare pictures, compare styles and choose the one you like!

Extract this package into a new folder and run **build.bat** as your normal
Windows user. Internet access is required to build. Open the resulting
`PowerPointLabs_6.1.0.2_Setup_XXXXXXXX.msi`, approve its displayed publisher
certificate, then start desktop PowerPoint. Close PowerPoint before installing,
repairing, upgrading or uninstalling. Install using the Windows account that
will run PowerPoint. No administrator elevation is needed for this per-user MSI.

The supplied add-on is named **PowerPointLabs 6.1.0.2** internally. Its filenames,
assembly names and Office registration retain that name.

## Contents and operation

One executable source file, `build.bat`, contains the PowerShell build logic,
WiX installer definition and necessary certificate installation/rollback code.
There are no tests, probes, monitoring, timing, analysis or evidence frameworks.
The 18 application files are the original payload, not builder scaffolding.
`TestInterface.dll` is a dependency of the supplied application and is retained.

The batch downloads a private .NET 8 SDK, Microsoft Mage 10.0.0 and WiX 3.14.1
into a unique temporary folder. It deletes that folder, including downloaded
archives and build intermediates, on completion or a handled failure. A forced
termination or power loss can leave that temporary folder behind. It does not
uninstall system runtimes or alter tool caches created by previous versions.
Each build therefore downloads its own build tools again.

Original application files and Signing are preserved. The MSI receives flat,
colocated manifests, DLLs and configuration. The original post-action assembly
reference is corrected from PostInstall to PowerPointLabs. Mage signs the
application manifest, updates its deployment reference and hash, then signs the
deployment manifest with the same certificate used to sign the MSI. The original
DLLs are not recompiled or re-signed.

## Signing

Choose one:

* Leave Signing empty: generate a reusable 3072-bit RSA code-signing certificate.
  Save its encrypted private key as `Signing/CodeSigning.pfx` and its password
  as `Signing/CodeSigning.password.dpapi`, protected by the current Windows
  account on this computer. These are reused on subsequent builds.
* Supply `Signing/CodeSigning.pfx`: enter its password when prompted. When
  replacing a generated PFX, move its old `.password.dpapi` file out of Signing.
* Supply `Signing/CertificateThumbprint.txt`: one certificate thumbprint, for an
  accessible RSA code-signing private key in the current user's Personal store.

Do not supply both PFX and thumbprint. Generated certificates expire after three
years; this local signing process does not use an online timestamp service.
Preserve your key material securely. Generated DPAPI passwords are not portable
to another Windows account/computer. Private keys are never included in the MSI
and are ignored by Git. A supplied organization certificate requires its issuing
CA chain to be trusted on the destination machine.

The installer displays the exact certificate thumbprint and requires consent
before adding the public certificate to Current User Trusted Publishers. For a
self-signed certificate, it also adds it to Current User Trusted Root. It preserves
pre-existing trust, rolls back changes if installation fails and removes only
trust it owns on uninstall. Trust applies to other code signed by this key too.
Office security policies are not changed. Organization policy may prohibit local
publisher trust or the add-in even with a valid signature.

## Requirements

Windows 10/11, Windows PowerShell 5.1 and desktop PowerPoint. The destination
also needs .NET Framework 4.5 or later and Microsoft VSTO Runtime 2010 or later.
The temporary modern .NET SDK is a build tool; it does not replace those runtimes.
The MSI stops with an error if its runtime prerequisites are missing.

This simplified revision has been reviewed locally; Windows MSI installation,
certificate-store behavior and launching PowerPoint still require execution on
Windows. No completed end-to-end Windows run is claimed.

## Licensing and source

`build.bat` and the creator documentation are MIT licensed; see LICENSE.
The supplied PowerPointLabs application retains its GPLv2 license and third-party
components retain their existing licenses. See GPL-2.0.txt. The MIT license does
not relicense the bundled application or third-party DLLs.

## Pinned original source

The original GPLv2 PowerPointLabs source is included as a **Git submodule** at `upstream/PowerPointLabs`, pinned to commit [`79e6be4882b736a0cb4828e06a96286de9b3aed6`](https://github.com/PowerPointLabs/PowerPointLabs/commit/79e6be4882b736a0cb4828e06a96286de9b3aed6) (May 16, 2020). The upstream C# project at this revision declares application version 6.1.0.2.

To obtain this repository and its pinned original source:

```bat
git clone --recurse-submodules https://github.com/FredThompsonII/PowerPointLabsLives.git
```

For an existing clone:

```bat
git submodule update --init --recursive
```

See [SOURCE_PROVENANCE.md](SOURCE_PROVENANCE.md) for the exact revision, source attribution, and reproducibility commands.
Source provenance supplied with the original package:
https://github.com/FredThompsonII/PowerPointLabsLives/tree/79e6be4882b736a0cb4828e06a96286de9b3aed6
This source reference is provenance, not a claim that it reproduces the supplied
binaries. Do not publish generated signing material or locally built installers
to GitHub.

Microsoft deployment and signing references:
https://learn.microsoft.com/en-us/visualstudio/vsto/deploying-a-vsto-solution-by-using-windows-installer
https://learn.microsoft.com/en-us/dotnet/framework/tools/mage-exe-manifest-generation-and-editing-tool
