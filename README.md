# gh-push-new-pr

## Description

Push a branch to origin and open a pull request for it on GitHub where it has none, titled with the last commit's subject, with that version's CHANGELOG entry as its body.

Where the branch already has an open pull request it pushes the branch and leaves the pull request as it is. Either way it prints the pull request's URL, and only that, on stdout.

Its sibling for merging is [gh-ff-merge](https://github.com/thoran/gh-ff-merge).

## Installation

As a gh extension, run as `gh push-new-pr`:

```shell
$ gh extension install thoran/gh-push-new-pr
```

## Dependencies

- gh, signed in.
- Ruby, and the gems in the Gemfile.

## Usage

From the branch, once its last commit is ready for review:

```shell
$ gh push-new-pr
```

It opens the pull request against origin's default branch. To open it against another:

```shell
$ gh push-new-pr develop
```

The title is the last commit's subject. Where the subject begins with a version, as `x.y.z: summary`, the body is the CHANGELOG's entry for it without its first line, which the title already gives. The entry runs to the next version or `## ` heading, so both of these are read:

```
## 20261028

0.1.0: + the second thing.

1. + the second thing.
```

```
## [0.1.0] - 2026-10-28

### Added

- The second thing.
```

Where there is no version or no entry for it, the body is the commit's body.

The push is forced with a lease, so that a branch reworked since it was pushed replaces what was pushed, while a branch pushed to from elsewhere since stops it.

It stops, pushing nothing, where:

- there is no remote called origin;
- it isn't on a branch;
- no base branch is named and origin's default branch isn't known here;
- the branch is the base branch;
- the branch holds another branch which the base branch doesn't;
- the base branch has moved on since the branch was cut;
- the branch has nothing which the base branch hasn't.

## Notes

1. It fetches from, and pushes to, the remote called origin.
2. An open pull request's title and body aren't brought up to date. Where the commit has been reworked, edit them with `gh pr edit`.

## Contributing

1. Fork it... `https://github.com/thoran/gh-push-new-pr/fork`
2. Create your feature branch... `git checkout -b my-new-feature`
3. Commit your changes... `git commit -am 'Add some feature'`
4. Push to the branch... `git push origin my-new-feature`
5. Create a new pull request


## License

MIT
