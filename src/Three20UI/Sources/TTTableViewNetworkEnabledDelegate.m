//
// Copyright 2009-2011 Facebook
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//    http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.
//

#import "Three20UI/TTTableViewNetworkEnabledDelegate.h"

// UI
#import "Three20UI/TTTableHeaderDragRefreshView.h"
#import "Three20UI/TTTableFooterInfiniteScrollView.h"
#import "Three20UI/TTTableViewController.h"
#import "Three20UI/UIViewAdditions.h"

// UICommon
#import "Three20UICommon/TTGlobalUICommon.h"

// Network
#import "Three20Network/TTModel.h"

// Style
#import "Three20Style/TTGlobalStyle.h"
#import "Three20Style/TTDefaultStyleSheet+DragRefreshHeader.h"

// Core
#import "Three20Core/TTCorePreprocessorMacros.h"


// The number of pixels the table needs to be pulled down by in order to initiate the refresh.
static const CGFloat kRefreshDeltaY = -65.0f;

// The height of the refresh header when it is in its "loading" state.
static const CGFloat kHeaderVisibleHeight = 60.0f;

// The height of the infinite scroll footer view
static const CGFloat kInfiniteScrollFooterHeight = 40.0f;

// The height of the footer when we are not loading.
static const CGFloat kNoFooterHeight = 1.0f;

// The percentage of table scrolling to trigger infinite scroll agter
static const CGFloat kInfiniteScrollThreshold = 0.5f;

// The maximum number of tableView-heights of scrollable content remaining below the visible
// area needed to trigger an infinite scroll.
static const CGFloat kInfiniteScrollRemainingMultiplier = 2.0f;


///////////////////////////////////////////////////////////////////////////////////////////////////
///////////////////////////////////////////////////////////////////////////////////////////////////
///////////////////////////////////////////////////////////////////////////////////////////////////
@implementation TTTableViewNetworkEnabledDelegate

@synthesize headerView = _headerView, footerView = _footerView,
            dragRefreshEnabled = _dragRefreshEnabled,
            infiniteScrollEnabled = _infiniteScrollEnabled;

///////////////////////////////////////////////////////////////////////////////////////////////////
///////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark -
#pragma mark NSObject


///////////////////////////////////////////////////////////////////////////////////////////////////
- (id)initWithController:(TTTableViewController*)controller
         withDragRefresh:(BOOL)enableDragRefresh
      withInfiniteScroll:(BOOL)enableInfiniteScroll {
	self = [super initWithController:controller];
  if (self) {
    _dragRefreshEnabled = enableDragRefresh;
    _infiniteScrollEnabled = enableInfiniteScroll;

    // Hook up to the model to listen for changes.
    _model = [controller.model retain];
    [_model.delegates addObject:self];

    if (_dragRefreshEnabled) {
      // Add our refresh header
      _headerView = [[TTTableHeaderDragRefreshView alloc]
                     initWithFrame:CGRectMake(0,
                                              -_controller.tableView.bounds.size.height,
                                              _controller.tableView.width,
                                              _controller.tableView.bounds.size.height)];
      _headerView.autoresizingMask = UIViewAutoresizingFlexibleWidth;
      _headerView.backgroundColor = TTSTYLEVAR(tableRefreshHeaderBackgroundColor);
      [_headerView setStatus:TTTableHeaderDragRefreshPullToReload];
      [_controller.tableView addSubview:_headerView];


      // Grab the last refresh date if there is one.
      if ([_model respondsToSelector:@selector(loadedTime)] && enableDragRefresh) {
        NSDate* date = [_model performSelector:@selector(loadedTime)];

        if (nil != date) {
          [_headerView setUpdateDate:date];
        }
      }
    }

    if (_infiniteScrollEnabled) {
      _footerView = [[TTTableFooterInfiniteScrollView alloc]
                      initWithFrame:CGRectMake(0,
                                               0,
                                               _controller.tableView.width,
                                               kNoFooterHeight)];
      _footerView.autoresizingMask = UIViewAutoresizingFlexibleWidth;
      _controller.tableView.tableFooterView = _footerView;
    }
  }
  return self;
}


///////////////////////////////////////////////////////////////////////////////////////////////////
- (void)dealloc {
  _controller.tableView.tableFooterView = nil;
  [_model.delegates removeObject:self];
  [_headerView removeFromSuperview];
  TT_RELEASE_SAFELY(_headerView);
  TT_RELEASE_SAFELY(_footerView);
  TT_RELEASE_SAFELY(_model);

  [super dealloc];
}


///////////////////////////////////////////////////////////////////////////////////////////////////
///////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark -
#pragma mark UIScrollViewDelegate


///////////////////////////////////////////////////////////////////////////////////////////////////
- (void)scrollViewDidScroll:(UIScrollView*)scrollView {
  [super scrollViewDidScroll:scrollView];

  if (_dragRefreshEnabled) {
    if (scrollView.dragging && !_model.isLoading) {
      if (scrollView.contentOffset.y > kRefreshDeltaY
          && scrollView.contentOffset.y < 0.0f) {
        [_headerView setStatus:TTTableHeaderDragRefreshPullToReload];

      } else if (scrollView.contentOffset.y < kRefreshDeltaY) {
        [_headerView setStatus:TTTableHeaderDragRefreshReleaseToReload];
      }
    }

    // This is to prevent odd behavior with plain table section headers. They are affected by the
    // content inset, so if the table is scrolled such that there might be a section header abutting
    // the top, we need to clear the content inset.
    if (_model.isLoading) {
      if (scrollView.contentOffset.y >= 0) {
        _controller.tableView.contentInset = UIEdgeInsetsZero;

      } else if (scrollView.contentOffset.y < 0) {
        _controller.tableView.contentInset = UIEdgeInsetsMake(kHeaderVisibleHeight, 0, 0, 0);
      }
    }
  }

  // JM: Try loading more if required conditions are met.
  [self tryLoadingMoreIfNeeded:scrollView];
}


///////////////////////////////////////////////////////////////////////////////////////////////////
- (void)scrollViewDidEndDragging:(UIScrollView*)scrollView willDecelerate:(BOOL)decelerate {
  [super scrollViewDidEndDragging:scrollView willDecelerate:decelerate];

  if (_dragRefreshEnabled) {
    // If dragging ends and we are far enough to be fully showing the header view trigger a
    // load as long as we arent loading already
    if (scrollView.contentOffset.y <= kRefreshDeltaY && !_model.isLoading) {
      [[NSNotificationCenter defaultCenter]
       postNotificationName:@"DragRefreshTableReload" object:nil];
      [_model load:TTURLRequestCachePolicyNetwork more:NO];
    }
  }
}


///////////////////////////////////////////////////////////////////////////////////////////////////
///////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark -
#pragma mark TTModelDelegate


///////////////////////////////////////////////////////////////////////////////////////////////////
- (void)modelDidStartLoad:(id<TTModel>)model {
  if (_dragRefreshEnabled) {
    [_headerView setStatus:TTTableHeaderDragRefreshLoading];

    [UIView beginAnimations:nil context:NULL];
    [UIView setAnimationDuration:ttkDefaultFastTransitionDuration];
    if (_controller.tableView.contentOffset.y < 0) {
      _controller.tableView.contentInset = UIEdgeInsetsMake(kHeaderVisibleHeight, 0.0f, 0.0f, 0.0f);
    }
    [UIView commitAnimations];
  }
}


///////////////////////////////////////////////////////////////////////////////////////////////////
- (void)modelDidFinishLoad:(id<TTModel>)model {
  if (_dragRefreshEnabled) {
    [_headerView setStatus:TTTableHeaderDragRefreshPullToReload];

    [UIView beginAnimations:nil context:NULL];
    [UIView setAnimationDuration:ttkDefaultTransitionDuration];
    _controller.tableView.contentInset = UIEdgeInsetsZero;
    [UIView commitAnimations];

    if ([model respondsToSelector:@selector(loadedTime)]) {
      NSDate* date = [model performSelector:@selector(loadedTime)];
      [_headerView setUpdateDate:date];

    } else {
      [_headerView setCurrentDate];
    }
  }

  // JM: Try loading more if the required conditions are met. We call this here because even
  // after loading, it's possible that we haven't accumulated enough remaining height and we
  // need to load More again. This behavior is particularly needed for a KLMultiModelModel with
  // multiple More submodels to work correctly.
  if (![self tryLoadingMoreIfNeeded:_controller.tableView]) {

    // If we're not loading again and infinite scroll is enabled, then hide the footer.
    if (_infiniteScrollEnabled) {

      // JM: Set footer height to hide footer. Re-assign footerView so table recognizes new height.
      TTTableFooterInfiniteScrollView* footerView = _footerView;
      footerView.height = kNoFooterHeight;
      [footerView setLoading:NO];

      // JM: only re-assign if it's currently being shown, otherwise controller could be overriding.
      if (_controller.tableView.tableFooterView == footerView) {
        _controller.tableView.tableFooterView = footerView;
      }
    }
  }
}


///////////////////////////////////////////////////////////////////////////////////////////////////
- (void)model:(id<TTModel>)model didFailLoadWithError:(NSError*)error {
  if (_dragRefreshEnabled) {
    [_headerView setStatus:TTTableHeaderDragRefreshPullToReload];

    [UIView beginAnimations:nil context:NULL];
    [UIView setAnimationDuration:ttkDefaultTransitionDuration];
    _controller.tableView.contentInset = UIEdgeInsetsZero;
    [UIView commitAnimations];
  }
}


///////////////////////////////////////////////////////////////////////////////////////////////////
- (void)modelDidCancelLoad:(id<TTModel>)model {
  if (_dragRefreshEnabled) {
    [_headerView setStatus:TTTableHeaderDragRefreshPullToReload];

    [UIView beginAnimations:nil context:NULL];
    [UIView setAnimationDuration:ttkDefaultTransitionDuration];
    _controller.tableView.contentInset = UIEdgeInsetsZero;
    [UIView commitAnimations];
  }
}


///////////////////////////////////////////////////////////////////////////////////////////////////
///////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark -
#pragma mark Public

///////////////////////////////////////////////////////////////////////////////////////////////////
- (CGFloat)headerVisibleHeight {
  return kHeaderVisibleHeight;
}

///////////////////////////////////////////////////////////////////////////////////////////////////
- (BOOL)tryLoadingMoreIfNeeded:(UIScrollView*)scrollView {

  // JM: If infiniteScroll is enabled and the model is not currently loading.
  if (_infiniteScrollEnabled && !_model.isLoading) {

    // JM: Calculate the height of scrollable content remaining below the visible area.
    CGFloat scrollRemaining = scrollView.contentSize.height - scrollView.height - scrollView.contentOffset.y;

    // JM: Ask the controller if we should load More based on the remaining height. If the
    // controller doesn't respond then just compare remaining height to constant multiple of
    // the tableView height.
    BOOL shouldLoad;
    if ([_controller respondsToSelector:@selector(shouldLoadAtScrollRemaining:)]) {
      shouldLoad = [(id <TTTableNetworkEnabledTableViewController>)_controller
                    shouldLoadAtScrollRemaining:scrollRemaining];

    } else {
      shouldLoad = scrollRemaining < (kInfiniteScrollRemainingMultiplier * scrollView.height);
    }

    if (shouldLoad) {
      [_model load:TTURLRequestCachePolicyDefault more:YES];

      // JM: Set footer height to make sure loading indicator is visible.
      // Re-assign footerView so table recognizes new height.
      TTTableFooterInfiniteScrollView* footerView = _footerView;
      footerView.height = kInfiniteScrollFooterHeight;
      [footerView setLoading:YES];
      _controller.tableView.tableFooterView = footerView;

      return YES;
    }
  }

  return NO;
}



@end
