# fusion360-post-grbl-plasma

Fusion360 Post processor for grbl based plasma cutters. Support Z movement with pierce height and delay for lead-ins.

## Install

### Recommended

Copy the `grbl_plasma.cps` into your personal post directory. This should make it available under the `Personal - local` library.

See this knowledge base article for details:

https://knowledge.autodesk.com/support/fusion-360/learn-explore/caas/sfdcarticles/sfdcarticles/How-to-add-a-Post-Processor-to-your-Personal-Posts-in-Fusion-360.html

### Really just put it anywhere

You can actually just store the `grbl_plasma.cps` file anywhere. When you create a post, select `browse` and point to the folder where the `cps` file is saved.

## Usage

### Setup

Setup your project as normal, just make sure you set the following to avoid errors.

* Operation Type: Cutting
* WSC Offset: 1 (or as appropriate)

### Tool Paths

1. Select the Fabrication tab.
1. Select Cutting tool path.

#### Set up your tool

With plasma cutting you will need to add a tool with speeds and Kerf width based on the material you are cutting.

I'm setting up a separate tool and saving them to my cloud library for various metal thickness. This will vary by your plasma cutter, so see your factory manual.

For Hypertherm plasma cutters, you can find the machine torch cut chart here: https://www.hypertherm.com/Download?fileId=HYP189352&zip=False

#### 2D Profile

Set up your profiles, heights, ect... as appropriate for your job. The following settings are required.

* Tool - Cutting Mode: `Through - auto`
* Passes - Compensation Type: `In computer`

---

## Acknowledgements

This code is based on published post-processors available here:

* [Grbl Laser](https://cam.autodesk.com/posts/post.php?name=grbl%20laser)
* [Mach3 Plasma](https://cam.autodesk.com/posts/post.php?name=mach3%20plasma)

## Disclaimers

Use this code at your own risk.

I've tested this code on my own machine (MillRight Mega V XL with a Hypertherm 45xp), but no guarantees or warranty are provided. By using this code you accept full responsibility for any damage to yourself, machine or projects.

Good luck, stay safe and have fun!

---

MillRight, Hypertherm, GRBL, Fusion360 and Mach3 are all trademarked by their respective owners. This project has no affiliation with any of those companies or projects.
