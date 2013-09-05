require 'rainbow'
require 'grit'

module Bugspots
  Fix = Struct.new(:message, :date, :files)
  Spot = Struct.new(:file, :score)

  def self.scan(repo, branch = "master", depth = 500, regex = nil, max_age = nil, min_age = nil)
    repo = Grit::Repo.new(repo)
    unless repo.branches.find { |e| e.name == branch }
      raise ArgumentError, "no such branch in the repo: #{branch}"
    end
    fixes = []

    regex ||= /\b(fix(es|ed)?|close(s|d)?)\b/i

    tree = repo.tree(branch)

    if max_age and !min_age  #kludge to account for passing of nil max_age resulting in git rev_list assuming it is 0
          commit_list = repo.git.rev_list({:max_count => false, :no_merges => true, :pretty => "raw", :timeout => false, :max_age => max_age}, branch)
    elif min_age and !max_age
          commit_list = repo.git.rev_list({:max_count => false, :no_merges => true, :pretty => "raw", :timeout => false, :min_age =>  min_age}, branch)
    elif min_age and max_age
          commit_list = repo.git.rev_list({:max_count => false, :no_merges => true, :pretty => "raw", :timeout => false, :max_age => max_age, :min_age =>  min_age}, branch)
    else #neither true
      commit_list = repo.git.rev_list({:max_count => false, :no_merges => true, :pretty => "raw", :timeout => false}, branch)
    end

    Grit::Commit.list_from_string(repo, commit_list).each do |commit|
      if commit.message =~ regex
        files = commit.stats.files.map {|s| s.first}.select{ |s| tree/s }
        fixes << Fix.new(commit.short_message, commit.date, files)
      end
    end

    hotspots = Hash.new(0)
    fixes.each do |fix|
      fix.files.each do |file|
        if min_age  # support changing alg to use min_time, i.e. time of most recent specified commit
          t = 1 - ((Time.at(min_age.to_i) - fix.date).to_f / (Time.at(min_age.to_i) - fixes.last.date))
        else
          t = 1 - ((Time.now - fix.date).to_f / (Time.now - fixes.last.date))
        end
        hotspots[file] += 1/(1+Math.exp((-12*t)+12))
      end
    end

    spots = hotspots.sort_by {|k,v| v}.reverse.collect do |spot|
      Spot.new(spot.first, sprintf('%.4f', spot.last))
    end

    return fixes, spots
  end
end
