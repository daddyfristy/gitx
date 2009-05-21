//
//  PBGitRevList.m
//  GitX
//
//  Created by Pieter de Bie on 17-06-08.
//  Copyright 2008 __MyCompanyName__. All rights reserved.
//

#import "PBGitRevList.h"
#import "PBGitGrapher.h"

#import "PBRevPoolDelegate.h"

#import "PBGitRepository.h"
#import "PBGitCommit.h"
#import "PBGitRevSpecifier.h"
#import "PBGitRevPool.h"
#import "PBGitRepository.h"

#include "git/oid.h"
#include <ext/stdio_filebuf.h>
#include <iostream>
#include <string>
#include <list>

using namespace std;

static void linearizeCommits(PBGitRevPool *pool, NSArray **commits, PBGitRepository *repository);


@implementation PBGitRevList

@synthesize commits;
- initWithRepository:(PBGitRepository *)repo
{
	repository = repo;
	[repository addObserver:self forKeyPath:@"currentBranch" options:0 context:nil];

	return self;
}

- (void) reload
{
	[self readCommitsForce: YES];
}

- (void) readCommitsForce: (BOOL) force
{
	// We use refparse to get the commit sha that we will parse. That way,
	// we can check if the current branch is the same as the previous one
	// and in that case we don't have to reload the revision list.

	// If no branch is selected, don't do anything
	if (![repository currentBranch])
		return;

	PBGitRevSpecifier* newRev = [repository currentBranch];
	NSString* newSha = nil;

	if (!force && newRev && [newRev isSimpleRef]) {
		newSha = [repository parseReference:[newRev simpleRef]];
		if ([newSha isEqualToString:lastSha])
			return;
	}
	lastSha = newSha;

	NSThread * commitThread = [[NSThread alloc] initWithTarget: self selector: @selector(walkRevisionListWithSpecifier:) object:newRev];
	[commitThread start];
}

- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object
	change:(NSDictionary *)change context:(void *)context
{
	if (object == repository)
		[self readCommitsForce: NO];
}

- (void) walkRevisionListWithSpecifier:(PBGitRevSpecifier *)rev
{
	grapher = [[PBGitGrapher alloc] initWithRepository:repository];
	commits = [NSMutableArray array];
	PBGitRevPool *pool = [[PBGitRevPool alloc] initWithRepository:repository];
	repository.commitPool = pool;
	pool.delegate = self;
	[pool loadRevisions:rev];
	commitsLoaded = 0;

	[self linearizeCommits];

	for (PBGitCommit *commit in commits)
		[grapher decorateCommit:commit];
	[self performSelectorOnMainThread:@selector(setCommits:) withObject:commits waitUntilDone:YES];
}


- (void)revPool:(PBGitRevPool *)pool encounteredCommit:(PBGitCommit *)commit
{
	[commits addObject: commit];
	if (++commitsLoaded % 1000 == 0)
		[self linearizeCommits];
}

-(void) linearizeCommits
{
	
	NSDate *start = [NSDate date];
	//bool tipChanged = false;

	/* Mark them and clear the indegree */
	for (PBGitCommit *commit in commits)
		commit->inDegree = 1;

	/* update the indegree */
	for (PBGitCommit *commit in commits)
	{
		for (PBGitCommit *parent in [commit parents]) {
			if (parent->inDegree)
				parent->inDegree++;
		}
	}

	
	/*
	 * find the tips
	 *
	 * tips are nodes not reachable from any other node in the list
	 *
	 * the tips serve as a starting set for the work queue.
	 */
	std::list<PBGitCommit *> tips;
	for (PBGitCommit *commit in commits)
	{
		if (commit->inDegree == 1)
			tips.push_back(commit);
	}

	NSMutableArray *sortedCommits = [NSMutableArray array];
//	int i = 0;
	while (tips.size())
	{
		PBGitCommit *commit = tips.front();
		tips.pop_front();

		for (PBGitCommit *parent in [commit parents]) {
			if (!parent->inDegree)
				continue;
			
			/*
			 * parents are only enqueued for emission
			 * when all their children have been emitted thereby
			 * guaranteeing topological order.
			 */
			if (--parent->inDegree == 1)
				tips.push_front(parent);
		}
		/*
		 * current item is a commit all of whose children
		 * have already been emitted. we can emit it now.
		 */
//		if (tipChanged || [*commits objectAtIndex: i++] != commit)
//		{
//			tipChanged = true;
//			[grapher decorateCommit: commit];
//		}
		[sortedCommits addObject:commit];
	}

	commits = sortedCommits;
	NSTimeInterval duration = [[NSDate date] timeIntervalSinceDate:start];
	NSLog(@"Sorted %i commits in %f seconds", [commits count], duration);
}

@end
