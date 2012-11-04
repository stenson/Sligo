//
//  ADKViewController.m
//  Sligo
//
//  Created by Robert Stenson on 11/3/12.
//  Copyright (c) 2012 __MyCompanyName__. All rights reserved.
//

#import "ADKViewController.h"

@interface ADKViewController () <UIScrollViewDelegate> {
    ADKAudioGraph *_audio;
    UIScrollView *_droneScroll;
}

@end

@implementation ADKViewController

- (void)viewDidLoad
{
    [super viewDidLoad];
    
    CGRect frame = [[UIScreen mainScreen] bounds];
    _droneScroll = [[UIScrollView alloc] initWithFrame:frame];
    _droneScroll.contentSize = CGSizeMake(frame.size.width, frame.size.height * 3);
    _droneScroll.backgroundColor = [UIColor colorWithWhite:0.0 alpha:1.0];
    _droneScroll.delegate = self;
    _droneScroll.showsVerticalScrollIndicator = NO;
    [self.view addSubview:_droneScroll];
    
	_audio = [[ADKAudioGraph alloc] init];
    [_audio power];
}

- (void)viewDidUnload
{
    [super viewDidUnload];
    // Release any retained subviews of the main view.
}

- (BOOL)shouldAutorotateToInterfaceOrientation:(UIInterfaceOrientation)interfaceOrientation
{
    return (interfaceOrientation != UIInterfaceOrientationPortraitUpsideDown);
}

- (void)scrollViewDidScroll:(UIScrollView *)scrollView
{
    CGFloat percentage = scrollView.contentOffset.y / scrollView.frame.size.height;
    [_audio updateDronePitchWithPercentage:percentage];
    _droneScroll.backgroundColor = [UIColor colorWithWhite:percentage alpha:1.0];
}

@end
