# test/gh-push-new-pr_test.rb

# 20261028
# 0.0.0

# Each test runs gh-push-new-pr as a subprocess in a clone of a bare repository
# made for the purpose, standing in for origin, with a fake gh first on the
# path, and asserts upon what is on origin and what gh was asked. The fake gh
# answers `gh pr view` from pull_request.json, failing where it is absent, as
# gh does with no pull request, and answers `gh pr create` with URL. Each call
# is written to calls, as a JSON array a line.

require 'json'
require 'minitest/autorun'
require 'open3'
require 'tmpdir'

BIN = File.expand_path('../gh-push-new-pr', __dir__)
URL = 'https://github.com/thoran/example/pull/1'

FAKE_GH = <<~'RUBY'
  #!/usr/bin/env ruby
  require 'json'
  directory = File.dirname(__FILE__)
  File.write(File.join(directory, 'calls'), "#{JSON.generate(ARGV)}\n", mode: 'a')
  if ARGV[0, 2] == ['pr', 'create']
    puts 'https://github.com/thoran/example/pull/1'
  else
    pull_request = File.join(directory, 'pull_request.json')
    exit 1 unless File.exist?(pull_request)
    puts File.read(pull_request)
  end
RUBY

CHANGELOG = <<~'TEXT'
  # CHANGELOG

  ## 20261028

  0.1.0: + the second thing.

  1. + the second thing.
  2. ~ the first thing.

  0.0.1: ~ the first thing, fixed.

  1. ~ the first thing.


  ## 20261027

  0.0.0: + the first thing.

  1. + the first thing.
TEXT

ENV['GIT_CONFIG_COUNT'] = '2'
ENV['GIT_CONFIG_KEY_0'] = 'commit.gpgsign'
ENV['GIT_CONFIG_VALUE_0'] = 'false'
ENV['GIT_CONFIG_KEY_1'] = 'advice.detachedHead'
ENV['GIT_CONFIG_VALUE_1'] = 'false'

def git(*arguments)
  system('git', *arguments, out: File::NULL, err: File::NULL) || raise("git #{arguments.join(' ')} failed")
end

def branch_from(start, branch, *messages)
  git('checkout', '-b', branch, start)
  messages.each{|message| git('commit', '--allow-empty', '-m', message)}
end

def commit_changelog(message, changelog = CHANGELOG, filename: 'CHANGELOG')
  File.write(filename, changelog)
  git('add', filename)
  git('commit', '-m', message)
end

def sha(ref)
  `git rev-parse --verify --quiet #{ref}`.strip
end

def origin_sha(branch)
  `git ls-remote origin refs/heads/#{branch}`.split.first
end

def fake_gh_directory
  @fake_gh_directory
end

def pull_request(state: 'OPEN')
  File.write(File.join(fake_gh_directory, 'pull_request.json'), JSON.generate(state: state, url: URL))
end

def gh_calls
  calls = File.join(fake_gh_directory, 'calls')
  File.exist?(calls) ? File.readlines(calls).collect{|line| JSON.parse(line)} : []
end

def created
  call = gh_calls.find{|arguments| arguments[0, 2] == ['pr', 'create']}
  call && call.drop(2).each_slice(2).to_h
end

def in_clone
  Dir.mktmpdir do |directory|
    Dir.chdir(directory) do
      @fake_gh_directory = File.join(directory, 'bin')
      Dir.mkdir(fake_gh_directory)
      File.write(File.join(fake_gh_directory, 'gh'), FAKE_GH)
      File.chmod(0755, File.join(fake_gh_directory, 'gh'))
      git('init', '--bare', '-b', 'master', 'origin.git')
      git('clone', 'origin.git', 'seed')
      Dir.chdir('seed'){git('commit', '--allow-empty', '-m', 'first'); git('push', 'origin', 'master')}
      git('clone', 'origin.git', 'clone')
      Dir.chdir('clone'){yield}
    end
  end
end

def push_new_pr(*arguments)
  path = "#{fake_gh_directory}#{File::PATH_SEPARATOR}#{ENV['PATH']}"
  stdout, stderr, status = Open3.capture3({'PATH' => path}, BIN, *arguments)
  [status.exitstatus, stdout, stderr]
end

describe "gh-push-new-pr" do
  describe "opening a pull request" do
    it "pushes the branch and opens a pull request titled with the subject, the CHANGELOG's entry its body" do
      in_clone do
        branch_from('master', 'second')
        commit_changelog('0.1.0: + the second thing.')
        status, stdout, _stderr = push_new_pr
        _(status).must_equal 0
        _(stdout).must_include URL
        _(origin_sha('second')).must_equal sha('second')
        _(created).must_equal('--base' => 'master', '--head' => 'second', '--title' => '0.1.0: + the second thing.', '--body' => "1. + the second thing.\n2. ~ the first thing.")
      end
    end

    it "ends the entry at the next date heading" do
      in_clone do
        branch_from('master', 'fix')
        commit_changelog('0.0.1: ~ the first thing, fixed.')
        push_new_pr
        _(created['--body']).must_equal '1. ~ the first thing.'
      end
    end

    it "ends the last entry at the end of the CHANGELOG" do
      in_clone do
        branch_from('master', 'first')
        commit_changelog('0.0.0: + the first thing.')
        push_new_pr
        _(created['--body']).must_equal '1. + the first thing.'
      end
    end

    it "reads an entry under a heading naming the version, from CHANGELOG.md" do
      in_clone do
        branch_from('master', 'second')
        commit_changelog('0.1.0: + the second thing.', "# Changelog\n\n## [0.1.0] - 2026-10-28\n\n### Added\n\n- The second thing.\n\n## [0.0.0] - 2026-10-27\n\n- The first thing.\n", filename: 'CHANGELOG.md')
        push_new_pr
        _(created['--body']).must_equal "### Added\n\n- The second thing."
      end
    end

    it "takes the commit's body where the subject has no version" do
      in_clone do
        branch_from('master', 'tidy', "Tidy the README.\n\nThe headings were uneven.")
        push_new_pr
        _(created['--title']).must_equal 'Tidy the README.'
        _(created['--body']).must_equal 'The headings were uneven.'
      end
    end

    it "takes the commit's body where the CHANGELOG has no entry for the version" do
      in_clone do
        branch_from('master', 'third')
        commit_changelog("0.2.0: + the third thing.\n\nThe third.")
        push_new_pr
        _(created['--body']).must_equal 'The third.'
      end
    end

    it "takes no version for one which only begins the same" do
      in_clone do
        branch_from('master', 'tenth')
        commit_changelog("0.1.00: + not the second thing.\n\nNot the second.")
        push_new_pr
        _(created['--body']).must_equal 'Not the second.'
      end
    end

    it "opens it against the base branch named" do
      in_clone do
        branch_from('master', 'develop', 'on develop')
        git('push', 'origin', 'develop')
        branch_from('develop', 'fix', 'the fix')
        status, _stdout, _stderr = push_new_pr('develop')
        _(status).must_equal 0
        _(created['--base']).must_equal 'develop'
      end
    end

    it "opens a new one where the branch's last pull request isn't open" do
      in_clone do
        branch_from('master', 'fix', 'the fix')
        pull_request(state: 'MERGED')
        push_new_pr
        _(created).wont_be_nil
      end
    end
  end

  describe "where the branch has an open pull request" do
    it "pushes the branch and prints the pull request's URL, opening none" do
      in_clone do
        branch_from('master', 'fix', 'the fix')
        pull_request
        status, stdout, stderr = push_new_pr
        _(status).must_equal 0
        _(stdout).must_equal "#{URL}\n"
        _(stderr).must_include 'fix already has an open pull request'
        _(origin_sha('fix')).must_equal sha('fix')
        _(created).must_be_nil
      end
    end

    it "pushes over the branch where it has been reworked since it was pushed" do
      in_clone do
        branch_from('master', 'fix', 'the fix')
        git('push', '--set-upstream', 'origin', 'fix')
        git('commit', '--amend', '--allow-empty', '-m', 'the fix, reworked')
        pull_request
        status, _stdout, _stderr = push_new_pr
        _(status).must_equal 0
        _(origin_sha('fix')).must_equal sha('fix')
      end
    end
  end

  describe "stopping" do
    it "stops where the branch has been pushed to from elsewhere since it was pushed from here" do
      in_clone do
        branch_from('master', 'fix', 'the fix')
        git('push', '--set-upstream', 'origin', 'fix')
        Dir.chdir('../seed'){git('fetch', 'origin'); git('checkout', 'fix'); git('commit', '--allow-empty', '-m', 'from elsewhere'); git('push', 'origin', 'fix')}
        elsewhere = origin_sha('fix')
        git('commit', '--amend', '--allow-empty', '-m', 'the fix, reworked')
        status, _stdout, _stderr = push_new_pr
        _(status).must_equal 1
        _(origin_sha('fix')).must_equal elsewhere
        _(gh_calls).must_be_empty
      end
    end

    it "stops where the base branch has moved on since the branch was cut" do
      in_clone do
        branch_from('master', 'fix', 'the fix')
        Dir.chdir('../seed'){git('commit', '--allow-empty', '-m', 'moved on'); git('push', 'origin', 'master')}
        status, _stdout, stderr = push_new_pr
        _(status).must_equal 1
        _(stderr).must_include 'master has moved on since fix was cut'
        _(origin_sha('fix')).must_be_nil
        _(gh_calls).must_be_empty
      end
    end

    it "stops where the branch holds another branch which the base branch doesn't" do
      in_clone do
        branch_from('master', 'first', 'the first')
        git('push', 'origin', 'first')
        git('fetch', 'origin')
        branch_from('first', 'second', 'the second')
        status, _stdout, stderr = push_new_pr
        _(status).must_equal 1
        _(stderr).must_include 'second holds origin/first'
        _(origin_sha('second')).must_be_nil
      end
    end

    it "stops where the branch has nothing which the base branch hasn't" do
      in_clone do
        branch_from('master', 'empty')
        status, _stdout, stderr = push_new_pr
        _(status).must_equal 1
        _(stderr).must_include "empty has nothing which origin/master doesn't."
        _(origin_sha('empty')).must_be_nil
      end
    end

    it "stops on the base branch" do
      in_clone do
        status, _stdout, stderr = push_new_pr
        _(status).must_equal 1
        _(stderr).must_include 'master is the base branch.'
      end
    end

    it "stops where it isn't on a branch" do
      in_clone do
        git('checkout', '--detach')
        status, _stdout, stderr = push_new_pr
        _(status).must_equal 1
        _(stderr).must_include 'Not on a branch.'
      end
    end

    it "stops where origin's default branch isn't known and none is named" do
      in_clone do
        git('remote', 'set-head', 'origin', '--delete')
        branch_from('master', 'fix', 'the fix')
        status, _stdout, stderr = push_new_pr
        _(status).must_equal 1
        _(stderr).must_include "origin's default branch isn't known here."
        _(origin_sha('fix')).must_be_nil
      end
    end

    it "stops where there is no remote called origin" do
      in_clone do
        git('remote', 'rename', 'origin', 'elsewhere')
        branch_from('master', 'fix', 'the fix')
        status, _stdout, stderr = push_new_pr
        _(status).must_equal 1
        _(stderr).must_include 'There is no remote called origin.'
      end
    end
  end

  describe "the command line" do
    it "shows usage and exits 0 upon -h and --help" do
      in_clone do
        ['-h', '--help'].each do |option|
          status, stdout, _stderr = push_new_pr(option)
          _(status).must_equal 0
          _(stdout).must_include 'Usage: gh push-new-pr'
        end
        _(gh_calls).must_be_empty
      end
    end

    it "stops upon an unknown option, and upon more than one base branch, before git or gh is run" do
      in_clone do
        branch_from('master', 'fix', 'the fix')
        [['-d'], ['--', 'master'], ['master', 'develop']].each do |arguments|
          status, stdout, _stderr = push_new_pr(*arguments)
          _(status).must_equal 1
          _(stdout).must_include 'Usage: gh push-new-pr'
        end
        _(origin_sha('fix')).must_be_nil
        _(gh_calls).must_be_empty
      end
    end
  end
end
