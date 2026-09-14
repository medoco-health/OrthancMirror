# medoco's Orthanc fork

This is a fork of [jodogne/OrthancMirror](https://github.com/jodogne/OrthancMirror), the read-only GitHub mirror of the official Mercurial repository. It exists to carry one patch to Orthanc's DICOM C-Get SCU, and to publish a build of it to our own registry.

Orthanc is GPLv3. This fork is public because distributing a modified binary obliges us to offer the modified source, and a public fork is the most direct way to do that. Every image we build carries an `org.opencontainers.image.revision` label pointing at the commit it came from.

## What we changed

One thing, in two files:

**Orthanc's C-Get SCU proposed only uncompressed transfer syntaxes.** When Orthanc retrieves a study with C-Get it is also the C-Store SCP receiving it, so it decides which transfer syntaxes are allowed. It offered only LittleEndianExplicit and LittleEndianImplicit, which forced the remote modality to decompress everything before sending. Retrieving JPEG 2000 photographs from our DICOM node inflated a 103 MB study to about 1 GB and timed the association out.

The fix proposes the syntaxes already listed in `AcceptedTransferSyntaxes`, and gives each syntax its own presentation context so the peer can pick per instance. See the commit message on `medoco/main` for the full reasoning, including why the second half is what makes the first half work.

Measured: stock Orthanc received 153 of 195 instances as roughly 1 GB before aborting after 5m19s. Patched, it received all 195 as 103 MB in 15.4s. Those numbers come from a build of this patch against Orthanc mainline, before the fork existed; the code here is the same change applied to the 1.13.0 release.

## Branch layout

| branch        | what it is                                                   | who writes to it                    |
| ------------- | ------------------------------------------------------------ | ----------------------------------- |
| `master`      | untouched mirror of upstream                                 | nobody -- only `git fetch upstream` |
| `medoco/main` | an upstream release commit plus our patch and this directory | merged pull requests only           |
| `feature/*`   | one change, reviewed into `medoco/main`                      | whoever is working                  |

**Never commit to `master`.** Keeping it identical to upstream is what lets `git fetch upstream && git merge --ff-only upstream/master` always work, and lets anyone compare our fork against upstream in one click. That comparison is the point of having forked rather than kept a private patch file.

Remotes, on a fresh clone:

```bash
git clone https://github.com/medoco-health/OrthancMirror.git
cd OrthancMirror
git remote add upstream https://github.com/jodogne/OrthancMirror.git
git fetch upstream
```

## Versioning

```
<upstream Orthanc version>-medoco.<patch level>

1.13.0-medoco.1
```

The two halves answer the only two questions anyone asks about one of these builds. **The Orthanc half** says which upstream release it is, which is what decides whether existing plugins still load -- they use Orthanc's versioned C API, and we do not rebuild them. **The medoco half** says which revision of our own changes it carries.

Bump the patch level whenever anything in this fork changes. Reset it to 1 when rebasing onto a new Orthanc release, because the first half already changed.

The same string is used for the git tag and the image tag, so a running container can be traced to a commit without looking anything up.

One wart worth knowing: under strict SemVer, `1.13.0-medoco.1` is a *pre-release* of 1.13.0 and therefore sorts *before* it, which is backwards -- ours is 1.13.0 plus changes. Nothing in this pipeline compares versions, and deployments pin an exact tag, so it costs nothing today. It is written down here so that whoever later adds a tool that does compare versions is not surprised by it. (`+medoco.1` would have been the correct SemVer, but `+` is not a legal character in a Docker tag.)

### The image

```
cr.medoco.health/medoco/orthanc:1.13.0-medoco.1
```

It contains the patched `Orthanc` binary at `/usr/local/sbin/Orthanc`, on Ubuntu 26.04, labelled with the commit it was built from. `docker run --rm <image>` prints its version, which is the quickest way to check what a tag really holds.

That is everything this repository publishes. How the binary reaches a deployment -- copied into another image, mounted, installed -- is the consumer's business, and deliberately not described here: this fork should not need to know or care what runs it.

## Building and pushing

There is deliberately no CI. These builds happen a few times a year, they need considerable resources, and every one of them should be a decision someone made rather than something a merge triggered.

```bash
docker login cr.medoco.health

./medoco/build.sh 1            # build 1.13.0-medoco.1 and tag it locally
./medoco/build.sh 1 --push     # ... and push the image and the git tag
```

The script reads the Orthanc version out of the CMake parameters rather than trusting you to type it, and builds from `git archive HEAD` so the context is exactly the committed tree. Everything that could stop a build being published -- a dirty tree, a tag that already exists, the wrong branch, no registry credentials -- is checked before the hour of compiling starts rather than after it. The image is tagged in git only once it has been pushed, so a failed push leaves nothing behind to clean up.

Released builds are cut from `medoco/main`. Building from a feature branch works and is the way to try a change out; `--push` from one is refused.

After building, the script runs `Orthanc --version` out of the fresh image, so a broken build fails here rather than in the registry.

Consumers then pin the new tag wherever they reference the image. Nothing in this repository needs to change for that.

## Moving to a new Orthanc release

The mirror carries almost no usable tags -- there are four, and they are leftovers like `dcmtk-3.6.1`. Release commits are still easy to find, because the conversion keeps their subject lines:

```bash
git fetch upstream
git log --oneline upstream/master --grep='^Orthanc-1\.14\.0$'
```

That commit is the real release: it is the one that sets `ORTHANC_VERSION` in `OrthancFramework/Resources/CMake/OrthancFrameworkParameters.cmake`. Then:

```bash
git checkout medoco/main
git rebase --onto <release commit> <previous release commit>
```

If upstream has touched the code we patched, the rebase conflicts, which is exactly the signal we want -- it means someone has to read the new code before we ship a build of it. If it rebases cleanly, build with the patch level reset to 1.

**Before shipping a new upstream release, check whether our patch is still needed.** If upstream has fixed this themselves, the right move is to drop our commit and go back to stock Orthanc, not to keep carrying a patch that no longer does anything.

## GPLv3 housekeeping

- The fork is public, and the `org.opencontainers.image.source` and `.revision` labels on every image point at it. That is the source offer.
- GPLv3 section 5(a) asks that modified files carry prominent notices that they were changed and when. The commit history on `medoco/main` carries that: each change is one commit, attributed and dated, against a named upstream release.
- Orthanc's own licence and copyright files are untouched, and must stay that way.
