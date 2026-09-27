import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ifallmusic/services/yt_music_service.dart';

/// Builds one playlist-shelf browse page, optionally ending in a continuation
/// row like real shelf responses do.
Map<String, dynamic> playlistPage({
  required List<String> videoIds,
  String? continuation,
}) {
  return <String, dynamic>{
    'contents': <String, dynamic>{
      'singleColumnBrowseResultsRenderer': <String, dynamic>{
        'tabs': <dynamic>[
          <String, dynamic>{
            'tabRenderer': <String, dynamic>{
              'content': <String, dynamic>{
                'sectionListRenderer': <String, dynamic>{
                  'contents': <dynamic>[
                    <String, dynamic>{
                      'musicPlaylistShelfRenderer': <String, dynamic>{
                        'contents': <dynamic>[
                          for (final String id in videoIds)
                            <String, dynamic>{
                              'musicResponsiveListItemRenderer':
                                  <String, dynamic>{
                                    'playlistItemData': <String, dynamic>{
                                      'videoId': id,
                                    },
                                    'flexColumns': <dynamic>[
                                      <String, dynamic>{
                                        'musicResponsiveListItemFlexColumnRenderer':
                                            <String, dynamic>{
                                              'text': <String, dynamic>{
                                                'runs': <dynamic>[
                                                  <String, dynamic>{
                                                    'text': 'Track $id',
                                                  },
                                                ],
                                              },
                                            },
                                      },
                                      <String, dynamic>{
                                        'musicResponsiveListItemFlexColumnRenderer':
                                            <String, dynamic>{
                                              'text': <String, dynamic>{
                                                'runs': <dynamic>[
                                                  <String, dynamic>{
                                                    'text': 'Artist $id',
                                                  },
                                                ],
                                              },
                                            },
                                      },
                                    ],
                                  },
                            },
                          if (continuation != null)
                            <String, dynamic>{
                              'continuationItemRenderer': <String, dynamic>{
                                'continuationEndpoint': <String, dynamic>{
                                  'continuationCommand': <String, dynamic>{
                                    'token': continuation,
                                  },
                                },
                              },
                            },
                        ],
                      },
                    },
                  ],
                },
              },
            },
          },
        ],
      },
    },
  };
}

void main() {
  test('browseTracks fetches a playlist shelf and follows continuations',
      () async {
    final List<RequestOptions> calls = <RequestOptions>[];
    final Dio dio = Dio();
    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (RequestOptions options, RequestInterceptorHandler handler) {
          calls.add(options);
          final bool firstPage =
              !options.queryParameters.containsKey('continuation');
          if (firstPage) {
            expect(options.data['browseId'], 'VLPLtestlist123');
          }
          handler.resolve(
            Response<Map<String, dynamic>>(
              requestOptions: options,
              statusCode: 200,
              data: firstPage
                  ? playlistPage(
                      videoIds: <String>['vid00000001', 'vid00000002'],
                      continuation: 'page-two-token',
                    )
                  : playlistPage(videoIds: <String>['vid00000003']),
            ),
          );
        },
      ),
    );

    final YtMusicService service = YtMusicService(dio: dio);
    final tracks = await service.browseTracks('VLPLtestlist123');

    expect(calls, hasLength(2));
    expect(calls[1].queryParameters['continuation'], 'page-two-token');
    expect(tracks.map((t) => t.id),
        <String>['vid00000001', 'vid00000002', 'vid00000003']);
    expect(tracks.first.title, 'Track vid00000001');
    expect(tracks.first.artist, 'Artist vid00000001');
    service.close();
  });

  test('browseTracks dedupes repeated ids across pages', () async {
    final Dio dio = Dio();
    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (RequestOptions options, RequestInterceptorHandler handler) {
          final bool firstPage =
              !options.queryParameters.containsKey('continuation');
          handler.resolve(
            Response<Map<String, dynamic>>(
              requestOptions: options,
              statusCode: 200,
              data: firstPage
                  ? playlistPage(
                      videoIds: <String>['vid00000001', 'vid00000002'],
                      continuation: 'page-two-token',
                    )
                  : playlistPage(videoIds: <String>['vid00000002']),
            ),
          );
        },
      ),
    );

    final YtMusicService service = YtMusicService(dio: dio);
    final tracks = await service.browseTracks('VLPLtestlist123');
    expect(tracks.map((t) => t.id), <String>['vid00000001', 'vid00000002']);
    service.close();
  });

  test('browseTracks respects the limit without extra pages', () async {
    int calls = 0;
    final Dio dio = Dio();
    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (RequestOptions options, RequestInterceptorHandler handler) {
          calls++;
          handler.resolve(
            Response<Map<String, dynamic>>(
              requestOptions: options,
              statusCode: 200,
              data: playlistPage(
                videoIds: <String>['vid00000001', 'vid00000002'],
                continuation: 'page-two-token',
              ),
            ),
          );
        },
      ),
    );

    final YtMusicService service = YtMusicService(dio: dio);
    final tracks = await service.browseTracks('VLPLtestlist123', limit: 2);
    expect(tracks, hasLength(2));
    expect(calls, 1);
    service.close();
  });
}
