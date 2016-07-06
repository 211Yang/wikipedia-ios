//
//  WMFImageURLParsingTests.m
//  Wikipedia
//
//  Created by Brian Gerstle on 3/4/15.
//  Copyright (c) 2015 Wikimedia Foundation. All rights reserved.
//

#import <UIKit/UIKit.h>
#import <XCTest/XCTest.h>
#import "WMFImageURLParsing.h"

#define HC_SHORTHAND 1
#import <OCHamcrest/OCHamcrest.h>

@interface WMFImageURLParsingTests : XCTestCase

@end

@implementation WMFImageURLParsingTests

- (void)testNoPrefixExample {
    NSString* testURL = @"//upload.wikimedia.org/wikipedia/commons/thumb/4/41/Iceberg_with_hole_near_Sandersons_Hope_2007-07-28_2.jpg/Iceberg_with_hole_near_Sandersons_Hope_2007-07-28_2.jpg";
    assertThat(WMFParseImageNameFromSourceURL(testURL),
               is(equalTo(@"Iceberg_with_hole_near_Sandersons_Hope_2007-07-28_2.jpg")));
}

- (void)testImageWithOneExtensionExample {
    NSString* testURL = @"//upload.wikimedia.org/wikipedia/commons/thumb/4/41/Iceberg_with_hole_near_Sandersons_Hope_2007-07-28_2.jpg/640px-Iceberg_with_hole_near_Sandersons_Hope_2007-07-28_2.jpg";
    assertThat(WMFParseImageNameFromSourceURL(testURL),
               is(equalTo(@"Iceberg_with_hole_near_Sandersons_Hope_2007-07-28_2.jpg")));
}

- (void)testImageWithTwoExtensionsExample {
    NSString* testURL = @"http://upload.wikimedia.org/wikipedia/commons/thumb/3/34/Access_to_drinking_water_in_third_world.svg/320px-Access_to_drinking_water_in_third_world.svg.png";
    assertThat(WMFParseImageNameFromSourceURL(testURL),
               is(equalTo(@"Access_to_drinking_water_in_third_world.svg")));
}

- (void)testImageWithPeriodInFileNameExample {
    NSString* testURL = @"//upload.wikimedia.org/wikipedia/commons/thumb/e/e6/Claude_Monet%2C_1870%2C_Le_port_de_Trouville_%28Breakwater_at_Trouville%2C_Low_Tide%29%2C_oil_on_canvas%2C_54_x_65.7_cm%2C_Museum_of_Fine_Arts%2C_Budapest.jpg/360px-Claude_Monet%2C_1870%2C_Le_port_de_Trouville_%28Breakwater_at_Trouville%2C_Low_Tide%29%2C_oil_on_canvas%2C_54_x_65.7_cm%2C_Museum_of_Fine_Arts%2C_Budapest.jpg";
    assertThat(WMFParseImageNameFromSourceURL(testURL),
               is(equalTo(@"Claude_Monet%2C_1870%2C_Le_port_de_Trouville_%28Breakwater_at_Trouville%2C_Low_Tide%29%2C_oil_on_canvas%2C_54_x_65.7_cm%2C_Museum_of_Fine_Arts%2C_Budapest.jpg")));
}

- (void)testNormalizedImageWithPeriodInFileNameExample {
    NSString* testURL    = @"//upload.wikimedia.org/wikipedia/commons/thumb/e/e6/Claude_Monet%2C_1870%2C_Le_port_de_Trouville_%28Breakwater_at_Trouville%2C_Low_Tide%29%2C_oil_on_canvas%2C_54_x_65.7_cm%2C_Museum_of_Fine_Arts%2C_Budapest.jpg/360px-Claude_Monet%2C_1870%2C_Le_port_de_Trouville_%28Breakwater_at_Trouville%2C_Low_Tide%29%2C_oil_on_canvas%2C_54_x_65.7_cm%2C_Museum_of_Fine_Arts%2C_Budapest.jpg";
    NSString* normalized = WMFParseUnescapedNormalizedImageNameFromSourceURL(testURL);
    assertThat(normalized,
               is(equalTo(@"Claude Monet, 1870, Le port de Trouville (Breakwater at Trouville, Low Tide), oil on canvas, 54 x 65.7 cm, Museum of Fine Arts, Budapest.jpg")));
}

- (void)testNormalizedImageWithPeriodInFileNameFromURLExample {
    NSURL* testURL       = [NSURL URLWithString:@"//upload.wikimedia.org/wikipedia/commons/thumb/e/e6/Claude_Monet%2C_1870%2C_Le_port_de_Trouville_%28Breakwater_at_Trouville%2C_Low_Tide%29%2C_oil_on_canvas%2C_54_x_65.7_cm%2C_Museum_of_Fine_Arts%2C_Budapest.jpg/360px-Claude_Monet%2C_1870%2C_Le_port_de_Trouville_%28Breakwater_at_Trouville%2C_Low_Tide%29%2C_oil_on_canvas%2C_54_x_65.7_cm%2C_Museum_of_Fine_Arts%2C_Budapest.jpg"];
    NSString* normalized = WMFParseUnescapedNormalizedImageNameFromSourceURL(testURL);
    assertThat(normalized,
               is(equalTo(@"Claude Monet, 1870, Le port de Trouville (Breakwater at Trouville, Low Tide), oil on canvas, 54 x 65.7 cm, Museum of Fine Arts, Budapest.jpg")));
}

- (void)testNormalizedEquality {
    NSString* one   = @"https://upload.wikimedia.org/wikipedia/commons/thumb/c/cb/Ole.PNG/440px-Olé.PNG";
    NSString* two   = @"https://upload.wikimedia.org/wikipedia/commons/thumb/c/cb/Ole.PNG/440px-Ol\u00E9.PNG";
    NSString* three = @"https://upload.wikimedia.org/wikipedia/commons/thumb/c/cb/Ole.PNG/440px-Ole\u0301.PNG";
    NSString* fn1   = WMFParseUnescapedNormalizedImageNameFromSourceURL(one);
    NSString* fn2   = WMFParseUnescapedNormalizedImageNameFromSourceURL(two);
    NSString* fn3   = WMFParseUnescapedNormalizedImageNameFromSourceURL(three);
    XCTAssertEqualObjects(fn1, fn2);
    XCTAssertEqualObjects(fn2, fn3);
}

- (void)testNormalizedEscapedEquality {
    NSString* one   = [@"https://upload.wikimedia.org/wikipedia/commons/thumb/c/cb/Ole.PNG/440px-Olé.PNG" stringByAddingPercentEscapesUsingEncoding:NSUTF8StringEncoding];
    NSString* two   = [@"https://upload.wikimedia.org/wikipedia/commons/thumb/c/cb/Ole.PNG/440px-Ol\u00E9.PNG" stringByAddingPercentEscapesUsingEncoding:NSUTF8StringEncoding];
    NSString* three = [@"https://upload.wikimedia.org/wikipedia/commons/thumb/c/cb/Ole.PNG/440px-Ole\u0301.PNG" stringByAddingPercentEscapesUsingEncoding:NSUTF8StringEncoding];
    NSString* fn1   = WMFParseUnescapedNormalizedImageNameFromSourceURL(one);
    NSString* fn2   = WMFParseUnescapedNormalizedImageNameFromSourceURL(two);
    NSString* fn3   = WMFParseUnescapedNormalizedImageNameFromSourceURL(three);
    XCTAssertEqualObjects(fn1, fn2);
    XCTAssertEqualObjects(fn2, fn3);
}

- (void)testImageWithMultiplePeriodsInFilename {
    NSString* testURLString =
        @"//upload.wikimedia.org/wikipedia/commons/thumb/c/cc/Blacksmith%27s_tools_-_geograph.org.uk_-_1483374.jpg/440px-Blacksmith%27s_tools_-_geograph.org.uk_-_1483374.jpg";
    assertThat(WMFParseImageNameFromSourceURL(testURLString),
               is(equalTo(@"Blacksmith%27s_tools_-_geograph.org.uk_-_1483374.jpg")));
}

- (void)testPrefixFromNoPrefixFileName {
    NSString* testURL = @"//upload.wikimedia.org/wikipedia/commons/thumb/4/41/Iceberg_with_hole_near_Sandersons_Hope_2007-07-28_2.jpg/Iceberg_with_hole_near_Sandersons_Hope_2007-07-28_2.jpg";

    XCTAssertEqual(WMFParseSizePrefixFromSourceURL(testURL), NSNotFound);
}

- (void)testPrefixFromImageWithOneExtensionExample {
    NSString* testURL = @"//upload.wikimedia.org/wikipedia/commons/thumb/4/41/Iceberg_with_hole_near_Sandersons_Hope_2007-07-28_2.jpg/640px-Iceberg_with_hole_near_Sandersons_Hope_2007-07-28_2.jpg";
    XCTAssertEqual(WMFParseSizePrefixFromSourceURL(testURL), 640);
}

- (void)testPrefixFromUrlWithoutImageFileLastPathComponent {
    NSString* testURL = @"//upload.wikimedia.org/wikipedia/commons/thumb/4/41/Iceberg_with_hole_near_Sandersons_Hope_2007-07-28_2.jpg/";
    XCTAssertEqual(WMFParseSizePrefixFromSourceURL(testURL), NSNotFound);
}

- (void)testPrefixFromZeroWidthImage {
    NSString* testURL = @"//upload.wikimedia.org/wikipedia/commons/thumb/4/41/Iceberg_with_hole_near_Sandersons_Hope_2007-07-28_2.jpg/0px-Iceberg_with_hole_near_Sandersons_Hope_2007-07-28_2.jpg";
    XCTAssertEqual(WMFParseSizePrefixFromSourceURL(testURL), NSNotFound);
}

- (void)testPrefixFromEmptyStringUrl {
    NSString* testURL = @"";
    XCTAssertEqual(WMFParseSizePrefixFromSourceURL(testURL), NSNotFound);
}

- (void)testPrefixFromNilUrl {
    NSString* testURL = nil;
    XCTAssertEqual(WMFParseSizePrefixFromSourceURL(testURL), NSNotFound);
}

- (void)testSizePrefixChangeOnNil {
    assertThat(WMFChangeImageSourceURLSizePrefix(nil, 123),
               is(equalTo(nil)));
}

- (void)testSizePrefixChangeOnEmptyString {
    assertThat(WMFChangeImageSourceURLSizePrefix(@"", 123),
               is(equalTo(@"")));
}

- (void)testSizePrefixChangeOnSingleSlashString {
    assertThat(WMFChangeImageSourceURLSizePrefix(@"/", 123),
               is(equalTo(@"/")));
}

- (void)testSizePrefixChangeOnSingleSpaceString {
    assertThat(WMFChangeImageSourceURLSizePrefix(@" ", 123),
               is(equalTo(@" ")));
}

- (void)testSizePrefixChangeOnSingleSlashSingleCharacterString {
    assertThat(WMFChangeImageSourceURLSizePrefix(@"/a", 123),
               is(equalTo(@"/a")));
}

- (void)testSizePrefixChangeOnURLWithoutSizePrefix {
    assertThat(WMFChangeImageSourceURLSizePrefix(@"https://upload.wikimedia.org/wikipedia/commons/a/a5/Buteo_magnirostris.jpg", 123),
               is(equalTo(@"https://upload.wikimedia.org/wikipedia/commons/thumb/a/a5/Buteo_magnirostris.jpg/123px-Buteo_magnirostris.jpg")));
}

- (void)testSizePrefixChangeOnURLWithSizePrefix {
    assertThat(WMFChangeImageSourceURLSizePrefix(@"//upload.wikimedia.org/wikipedia/commons/thumb/4/41/200px-Potato.jpg/", 123),
               is(equalTo(@"//upload.wikimedia.org/wikipedia/commons/thumb/4/41/123px-Potato.jpg/")));
}

- (void)testSizePrefixChangeOnlyEffectsLastPathComponent {
    assertThat(WMFChangeImageSourceURLSizePrefix(@"//upload.wikimedia.org/wikipedia/commons/thumb/200px-/4/41/200px-Potato.jpg/", 123),
               is(equalTo(@"//upload.wikimedia.org/wikipedia/commons/thumb/200px-/4/41/123px-Potato.jpg/")));
}

- (void)testSizePrefixChangeOnENWikiURL {
    assertThat(WMFChangeImageSourceURLSizePrefix(@"//upload.wikimedia.org/wikipedia/en/6/69/PercevalShooting.jpg", 123),
               is(equalTo(@"//upload.wikimedia.org/wikipedia/en/thumb/6/69/PercevalShooting.jpg/123px-PercevalShooting.jpg")));
}

- (void)testSizePrefixChangeOnURLEndingWithWikipedia {
    assertThat(WMFChangeImageSourceURLSizePrefix(@"//upload.wikimedia.org/wikipedia/", 123),
               is(equalTo(@"//upload.wikimedia.org/wikipedia/")));
}

- (void)testSizePrefixChangeOnURLEndingWithWikipediaAndDoubleSlashes {
    assertThat(WMFChangeImageSourceURLSizePrefix(@"//upload.wikimedia.org/wikipedia//", 123),
               is(equalTo(@"//upload.wikimedia.org/wikipedia//")));
}

- (void)testSVG {
    NSString* testURLString = @"//upload.wikimedia.org/wikipedia/commons/thumb/4/41/Iceberg_with_hole_near_Sandersons_Hope_2007-07-28_2.svg/640px-Iceberg_with_hole_near_Sandersons_Hope_2007-07-28_2.svg.png";
    assertThat(WMFParseImageNameFromSourceURL(testURLString),
               is(equalTo(@"Iceberg_with_hole_near_Sandersons_Hope_2007-07-28_2.svg")));
}

@end
