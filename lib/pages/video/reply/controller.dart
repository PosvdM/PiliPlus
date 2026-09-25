import 'package:PiliPlus/grpc/bilibili/main/community/reply/v1.pb.dart'
    show MainListReply, ReplyInfo;
import 'package:PiliPlus/grpc/reply.dart';
import 'package:PiliPlus/http/loading_state.dart';
import 'package:PiliPlus/models/common/video/video_type.dart';
import 'package:PiliPlus/pages/common/reply_controller.dart';
import 'package:PiliPlus/pages/video/controller.dart';
import 'package:PiliPlus/pages/video/introduction/pgc/controller.dart';
import 'package:PiliPlus/pages/video/introduction/ugc/controller.dart';
import 'package:PiliPlus/pages/video/reply/vote/reply_vote_mixin.dart';
import 'package:PiliPlus/services/breeze/breeze_content.dart';
import 'package:PiliPlus/services/breeze/breeze_rules.dart';
import 'package:PiliPlus/services/breeze/breeze_service.dart';
import 'package:PiliPlus/utils/id_utils.dart';
import 'package:get/get.dart';

class VideoReplyController extends ReplyController<MainListReply>
    with ReplyVoteMixin {
  VideoReplyController({
    required this.aid,
    required this.videoType,
    required this.heroTag,
  });
  int aid;
  final VideoType videoType;
  late final isPugv = videoType == VideoType.pugv;

  final String heroTag;
  late final videoCtr = Get.find<VideoDetailController>(tag: heroTag);

  @override
  dynamic get sourceId => IdUtils.av2bv(aid);

  BreezeRaw? breezePinnedRaw(ReplyInfo reply) {
    final isUgc = videoCtr.isUgc;
    String title = '';
    String upName = '';
    try {
      if (isUgc) {
        final detail = Get.find<UgcIntroController>(
          tag: heroTag,
        ).videoDetail.value;
        title = detail.title ?? '';
        upName = detail.owner?.name ?? '';
      } else {
        title =
            Get.find<PgcIntroController>(
              tag: heroTag,
            ).videoDetail.value.title ??
            '';
      }
    } catch (_) {}
    final mid = upMid?.toInt() ?? 0;
    return BreezeContent.fromPinnedReply(
      reply,
      upName: upName,
      upMid: mid > 0 ? '$mid' : '',
      title: title,
      url: isUgc
          ? 'https://www.bilibili.com/video/${IdUtils.av2bv(aid)}'
          : 'https://www.bilibili.com/bangumi/play/ep${videoCtr.epId}',
    );
  }

  @override
  bool customHandleResponse(bool isRefresh, Success<MainListReply> response) {
    final handled = super.customHandleResponse(isRefresh, response);
    if (isRefresh && hasUpTop) {
      final reply = response.response.upTop;
      // The title is part of the request; wait for it rather than send twice.
      BreezeService.prefetch(() {
        final raw = breezePinnedRaw(reply);
        return [if (raw != null && raw.title.isNotEmpty) raw];
      }, BreezeKind.pinned);
    }
    return handled;
  }

  @override
  List<ReplyInfo>? getDataList(MainListReply response) {
    return response.replies;
  }

  @override
  Future<LoadingState<MainListReply>> customGetData() => ReplyGrpc.mainList(
    oid: isPugv ? videoCtr.epId! : aid,
    type: videoType.replyType,
    mode: mode,
    cursorNext: cursorNext,
    offset: paginationReply?.nextOffset,
  );
}
