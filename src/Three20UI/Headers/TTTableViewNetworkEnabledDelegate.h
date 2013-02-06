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

#import "Three20UI/TTTableViewVarHeightDelegate.h"

// Network
#import "Three20Network/TTModelDelegate.h"

@class TTTableHeaderDragRefreshView, TTTableFooterInfiniteScrollView;
@protocol TTModel, TTTableNetworkEnabledTableViewController;

@interface TTTableViewNetworkEnabledDelegate : TTTableViewVarHeightDelegate {
  TTTableHeaderDragRefreshView*    _headerView;
  TTTableFooterInfiniteScrollView* _footerView;
  id<TTModel>                      _model;
  BOOL                             _dragRefreshEnabled;
  BOOL                             _infiniteScrollEnabled;
}

@property (nonatomic, retain) TTTableHeaderDragRefreshView* headerView;
@property (nonatomic, retain) TTTableFooterInfiniteScrollView* footerView;
@property (readonly) BOOL dragRefreshEnabled;
@property (readonly) BOOL infiniteScrollEnabled;

- (id)initWithController:(TTTableViewController*)controller
         withDragRefresh:(BOOL)enableDragRefresh
      withInfiniteScroll:(BOOL)enableInfiniteScroll;

// JM: Added so we can reference constant elsewhere.
- (CGFloat)headerVisibleHeight;


@end

@protocol TTTableNetworkEnabledTableViewController <NSObject>
@optional
- (BOOL)shouldLoadAtScrollRatio:(CGFloat)scrollRatio;

// JM: Added this method to the protocol because it performs better than
// triggering loading based on scrollRatio. If we have a very tall contentArea
// (relative to the table height) and we are scrolled well past the scrollRatio
// threshold, then may need to make many loads to achieve the desired ratio.
// By triggering off the remaining scroll area, the performance is the same
// regardless of total content size.
- (BOOL)shouldLoadAtScrollRemaining:(CGFloat)scrollRemaining;
@end
