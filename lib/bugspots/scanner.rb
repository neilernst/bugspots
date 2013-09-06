require 'rainbow'
require 'grit'

module Bugspots
  Fix = Struct.new(:message, :date, :files, :changes)
  Spot = Struct.new(:file, :score)

  def self.scan(repo, branch = "master", depth = 500, regex = nil, max_age = nil, min_age = nil)
    repo = Grit::Repo.new(repo)
    unless repo.branches.find { |e| e.name == branch }
      raise ArgumentError, "no such branch in the repo: #{branch}"
    end
    fixes = []

    regex ||= /\b(fix(es|ed)?|close(s|d)?)\b/i

    tree = repo.tree(branch)

      commit_list = repo.git.rev_list({:max_count => false, :no_merges => true, :pretty => "raw", :timeout => false, :max_age => max_age, :min_age =>  min_age}, branch)


    Grit::Commit.list_from_string(repo, commit_list).each do |commit|
      if commit.message =~ regex
        files = commit.stats.files.map {|s| s.first}.select{ |s| tree/s } # don't include files not in that branch's current treeish (ie. they were deleted.)
        fixes << Fix.new(commit.short_message, commit.date, files, files.length)
      end
    end

    tot_change = 0
    denom = 0
    avg = nil

    hotspots = Hash.new(0)
    fixes.each do |fix|
      if fix.changes > 0
        tot_change += fix.changes
        denom += 1
      end
      fix.files.each do |file|
        if min_age  # support changing alg to use min_time, i.e. time of most recent specified commit
          t = 1 - ((Time.at(min_age.to_i) - fix.date).to_f / (Time.at(min_age.to_i) - fixes.last.date))
        else
          t = 1 - ((Time.now - fix.date).to_f / (Time.now - fixes.last.date))
        end
        hotspots[file] += 1/(1+Math.exp((-12*t)+12))
      end
    end

    if denom != 0
      avg = tot_change.to_f / denom.to_f
    end
    puts "\t\tAvg # files per fix is ".foreground(:red) + avg.round(3).to_s
    spots = hotspots.sort_by {|k,v| v}.reverse.collect do |spot|
      Spot.new(spot.first, sprintf('%.4f', spot.last))
    end

    return fixes, spots
  end
end
