import 'package:flutter/material.dart';
import '../flutter_timetable.dart';

/// The [Timetable] widget displays calendar like view of the events that scrolls
/// horizontally through the days and vertical through the hours.
/// <img src="https://github.com/yourfriendken/flutter_timetable/raw/main/images/default.gif" width="400" />
class Timetable<T> extends StatefulWidget {
  /// [TimetableController] is the controller that also initialize the timetable.
  final TimetableController? controller;

  /// Renders for the cells the represent each hour that provides that [DateTime] for that hour
  final Widget Function(DateTime)? cellBuilder;

  /// Renders for the header that provides the [DateTime] for the day
  final Widget Function(DateTime)? headerCellBuilder;

  /// Timetable items to display in the timetable
  final List<TimetableItem<T>> items;

  /// Renders event card from `TimetableItem<T>` for each item
  final Widget Function(TimetableItem<T>)? itemBuilder;

  /// Renders hour label given [TimeOfDay] for each hour
  final Widget Function(TimeOfDay time)? hourLabelBuilder;

  /// Renders upper left corner of the timetable given the first visible date
  final Widget Function(DateTime current)? cornerBuilder;

  /// Snap to hour column. Default is `true`.
  final bool snapToDay;

  /// Snap animation curve. Default is `Curves.bounceOut`
  final Curve snapAnimationCurve;

  /// Snap animation duration. Default is 300 ms
  final Duration snapAnimationDuration;

  /// Color of indicator line that shows the current time. Default is `Theme.indicatorColor`.
  final Color? nowIndicatorColor;

  final void Function()? onChangeDate;

  /// The [Timetable] widget displays calendar like view of the events that scrolls
  /// horizontally through the days and vertical through the hours.
  /// <img src="https://github.com/yourfriendken/flutter_timetable/raw/main/images/default.gif" width="400" />
  const Timetable({
    super.key,
    this.controller,
    this.cellBuilder,
    this.headerCellBuilder,
    this.items = const [],
    this.itemBuilder,
    this.hourLabelBuilder,
    this.nowIndicatorColor,
    this.cornerBuilder,
    this.snapToDay = true,
    this.snapAnimationDuration = const Duration(milliseconds: 300),
    this.snapAnimationCurve = Curves.bounceOut,
    this.onChangeDate,
  });



  @override
  State<Timetable<T>> createState() => _TimetableState<T>();
}

class _TimetableState<T> extends State<Timetable<T>> {
  final _dayScrollController = ScrollController();
  final _dayHeadingScrollController = ScrollController();
  final _timeScrollController = ScrollController();
  double columnWidth = 50.0;
  TimetableController controller = TimetableController();
  final _key = GlobalKey();

  Color get nowIndicatorColor =>
      widget.nowIndicatorColor ?? Theme
          .of(context)
          .indicatorColor;
  int? _listenerId;

  @override
  void initState() {
    controller = widget.controller ?? controller;
    _listenerId = controller.addListener(_eventHandler);
    if (widget.items.isNotEmpty) {
      widget.items.sort((a, b) => a.start.compareTo(b.start));
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      adjustColumnWidth();
      final now = DateTime.now();

      final hourPosition =
          ((now.hour) * controller.cellHeight) - (controller.cellHeight / 2);

      _timeScrollController.animateTo(
        hourPosition,
        duration: widget.snapAnimationDuration,
        curve: widget.snapAnimationCurve,
      );
    });

    super.initState();
  }

  @override
  void dispose() {
    if (_listenerId != null) {
      controller.removeListener(_listenerId!);
    }
    _dayScrollController.dispose();
    _dayHeadingScrollController.dispose();
    _timeScrollController.dispose();
    super.dispose();
  }

  _eventHandler(TimetableControllerEvent event) async {


    if (event is TimetableJumpToRequested) {
      _jumpTo(event.date);
    }

    if (event is TimetableColumnsChanged) {
      final prev = controller.visibleDateStart;
      final now = DateTime.now();
      await adjustColumnWidth();
      _jumpTo(DateTime(prev.year, prev.month, prev.day, now.hour, now.minute));
      return;
    }

    if(event is TimetableNextWeek) {
      _snapToNextWeek();
      _updateVisibleDate();
    }

    if(event is TimetablePreviousWeek) {
      _snapToPrevWeek();
      _updateVisibleDate();
    }

    if (mounted) setState(() {});
  }

  Future adjustColumnWidth() async {
    final box = _key.currentContext?.findRenderObject() as RenderBox?;
    if (box == null) return;
    if (box.hasSize) {
      final size = box.size;
      final layoutWidth = size.width;
      final width =
          (layoutWidth - controller.timelineWidth) / controller.columns;
      if (width != columnWidth) {
        columnWidth = width;
        await Future.microtask(() => null);
        setState(() {});
      }
    }
  }

  bool _areEventsOverlapping<T>(TimetableItem<T> a, TimetableItem<T> b) {
    return a.start.isBefore(b.end) && b.start.isBefore(a.end);
  }

  Map<TimetableItem<T>, Map<String, double>> handleMap<T>(
      List<TimetableItem<T>> events,
      double columnWidth,
      double cellHeight,
      int startHour,) {
    final Map<TimetableItem<T>, Map<String, double>> resultMap = {};
    final List<List<TimetableItem<T>>> eventGroups = [];

    for (final event in events) {
      bool addedToGroup = false;
      for (final group in eventGroups) {
        bool overlaps = false;
        for (final groupedEvent in group) {
          if (_areEventsOverlapping(groupedEvent, event)) {
            overlaps = true;
            break;
          }
        }
        if (overlaps) {
          group.add(event);
          addedToGroup = true;
          break;
        }
      }
      if (!addedToGroup) {
        eventGroups.add([event]);
      }
    }

    for (final group in eventGroups) {
      final int groupSize = group.length;
      for (int i = 0; i < groupSize; i++) {
        final event = group[i];

        final double eventTop =
            (-startHour + event.start.hour + (event.start.minute / 60.0)) *
                cellHeight;
        final double eventHeight = event.duration.inMinutes * cellHeight / 60;

        final double individualWidth = columnWidth / groupSize;
        final double leftOffset = i * individualWidth;

        resultMap[event] = {
          'top': eventTop,
          'height': eventHeight,
          'width': individualWidth,
          'left': leftOffset,
        };
      }
    }

    return resultMap;
  }

  bool _isTableScrolling = false;
  bool _isHeaderScrolling = false;

  @override
  Widget build(BuildContext context) =>
      LayoutBuilder(
          key: _key,
          builder: (context, constraints) {
            return Column(
              children: [
                //Header
                SizedBox(
                  height: controller.headerHeight,
                  child: Row(
                    children: [
                      SizedBox(
                        width: controller.timelineWidth,
                        height: controller.headerHeight,
                        child: _buildCorner(),
                      ),
                      Expanded(
                        child: NotificationListener<ScrollNotification>(
                          onNotification: (notification) {
                            if (_isTableScrolling) return false;
                            if (notification is ScrollEndNotification) {
                              _snapToClosetWeek();
                              _updateVisibleDate();
                              _isHeaderScrolling = false;
                              return true;
                            }
                            _isHeaderScrolling = true;
                            _dayScrollController.jumpTo(
                              _dayHeadingScrollController.position.pixels,
                            );
                            return false;
                          },
                          child: ListView.builder(
                            scrollDirection: Axis.horizontal,
                            controller: _dayHeadingScrollController,
                            itemExtent: columnWidth,
                            itemBuilder: (context, i) =>
                                SizedBox(
                                  width: columnWidth,
                                  child: _buildHeaderCell(i),
                                ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                //Body
                Expanded(
                  child: NotificationListener<ScrollNotification>(
                    onNotification: (notification) {
                      if (_isHeaderScrolling) return false;

                      if (notification is ScrollEndNotification) {
                        _snapToClosetWeek();
                        //TODO: fix next
                        _updateVisibleDate();
                        _isTableScrolling = false;
                        return true;
                      }
                      _isTableScrolling = true;
                      _dayHeadingScrollController
                          .jumpTo(_dayScrollController.position.pixels);
                      return true;
                    },
                    child: SingleChildScrollView(
                      controller: _timeScrollController,
                      child: SizedBox(
                        height: controller.cellHeight *
                            (controller.endHour - controller.startHour + 1),
                        child: Row(
                          children: [
                            //Time Line
                            SizedBox(
                              width: controller.timelineWidth,
                              height: controller.cellHeight *
                                  (controller.endHour - controller.startHour +
                                      1),
                              child: Column(
                                children: [
                                  for (var i = controller.startHour;
                                  i < controller.endHour + 1;
                                  i++)
                                    SizedBox(
                                      height: controller.cellHeight,
                                      child: Center(
                                        child: _buildHour(
                                          TimeOfDay(hour: i, minute: 0),
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                            ),
                            //Cell
                            Expanded(
                              child: ListView.builder(
                                scrollDirection: Axis.horizontal,
                                // cacheExtent: 10000.0,
                                itemExtent: columnWidth,
                                controller: _dayScrollController,
                                itemBuilder: (context, index) {
                                  final date =
                                  controller.start.add(Duration(days: index));
                                  final events = widget.items
                                      .where((event) =>
                                      DateUtils.isSameDay(date, event.start))
                                      .toList();
                                  final now = DateTime.now();
                                  final isToday = DateUtils.isSameDay(
                                      date, now);

                                  final eventMap = handleMap<T>(
                                    events,
                                    columnWidth,
                                    controller.cellHeight,
                                    controller.startHour,
                                  );

                                  //A Day
                                  return Container(
                                    clipBehavior: Clip.none,
                                    width: columnWidth,
                                    height: controller.cellHeight *
                                        (controller.endHour -
                                            controller.startHour +
                                            1),
                                    child: Stack(
                                      clipBehavior: Clip.none,
                                      children: [
                                        //Bg
                                        Column(
                                          children: [
                                            for (int i = controller.startHour;
                                            i < controller.endHour + 1;
                                            i++)
                                              SizedBox(
                                                width: columnWidth,
                                                height: controller.cellHeight,
                                                child: Center(
                                                  child: _buildCell(
                                                      DateUtils.dateOnly(date)
                                                          .add(
                                                          Duration(hours: i))),
                                                ),
                                              ),
                                          ],
                                        ),
                                        //Event
                                        for (final TimetableItem<
                                            T> event in events)
                                          Positioned(
                                            top: eventMap[event]!['top'],
                                            width: eventMap[event]!['width'],
                                            height: eventMap[event]!['height'],
                                            left: eventMap[event]!['left'],
                                            child: _buildEvent(event),
                                          ),
                                        //Now Indicator
                                        if (isToday)
                                          Positioned(
                                            top: ((-controller.startHour +
                                                now.hour +
                                                (now.minute / 60.0)) *
                                                controller.cellHeight) -
                                                1,
                                            width: columnWidth,
                                            child: Stack(
                                              clipBehavior: Clip.none,
                                              children: [
                                                Container(
                                                  clipBehavior: Clip.none,
                                                  color: nowIndicatorColor,
                                                  height: 2,
                                                  width: columnWidth + 1,
                                                ),
                                                Positioned(
                                                  top: -2,
                                                  left: -2,
                                                  child: Container(
                                                    decoration: BoxDecoration(
                                                      shape: BoxShape.circle,
                                                      color: nowIndicatorColor,
                                                    ),
                                                    height: 6,
                                                    width: 6,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                      ],
                                    ),
                                  );
                                },
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            );
          });

  String _formatDate(DateTime date) =>
      "${_months[date.month - 1]}\n${date.day}";
  static const _months = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sept',
    'Oct',
    'Nov',
    'Dec'
  ];

  Widget _buildHeaderCell(int i) {
    final date = controller.start.add(Duration(days: i));
    if (widget.headerCellBuilder != null) {
      return widget.headerCellBuilder!(date);
    }
    final weight = DateUtils.isSameDay(date, DateTime.now()) //
        ? FontWeight.bold
        : FontWeight.normal;
    return Center(
      child: Text(
        _formatDate(date),
        style: TextStyle(fontSize: 12, fontWeight: weight),
        textAlign: TextAlign.center,
      ),
    );
  }

  Widget _buildCell(DateTime date) {
    if (widget.cellBuilder != null) return widget.cellBuilder!(date);

    return Container(
      decoration: BoxDecoration(
        border: Border.all(
          color: Theme
              .of(context)
              .dividerColor,
          width: 0.5,
        ),
      ),
    );
  }

  Widget _buildHour(TimeOfDay time) {
    if (widget.hourLabelBuilder != null) return widget.hourLabelBuilder!(time);
    return Text(time.format(context), style: const TextStyle(fontSize: 11));
  }

  Widget _buildCorner() {
    if (widget.cornerBuilder != null) {
      return widget.cornerBuilder!(controller.visibleDateStart);
    }
    return Center(
      child: Text(
        "${controller.visibleDateStart.year}",
        textAlign: TextAlign.center,
      ),
    );
  }

  String toTime(DateTime date) =>
      "${date.hour % 12}:${date.minute.toString().padLeft(2, "0")} ${date.hour >
          12 ? 'PM' : 'AM'}";

  Widget _buildEvent(TimetableItem<T> event) {
    if (widget.itemBuilder != null) return widget.itemBuilder!(event);
    return Container(
      padding: EdgeInsets.only(
        right: 2,
      ),
      decoration: BoxDecoration(
        color: Theme
            .of(context)
            .colorScheme
            .surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: Theme
              .of(context)
              .dividerColor,
          width: 0.5,
        ),
      ),
      child: Text(
        "${toTime(event.start)} - ${toTime(event.end)}",
        style: TextStyle(
          fontSize: 10,
          color: Theme
              .of(context)
              .colorScheme
              .onSurface,
        ),
      ),
    );
  }

  bool _isSnapping = false;

  Future _snapToCloset() async {
    if (_isSnapping || !widget.snapToDay) return;
    _isSnapping = true;
    await Future.microtask(() => null);
    final snapPosition =
        ((_dayScrollController.offset) / columnWidth).round() * columnWidth;
    _dayScrollController.animateTo(
      snapPosition,
      duration: widget.snapAnimationDuration,
      curve: widget.snapAnimationCurve,
    );
    _dayHeadingScrollController.animateTo(
      snapPosition,
      duration: widget.snapAnimationDuration,
      curve: widget.snapAnimationCurve,
    );
    _isSnapping = false;
  }

  Future _snapToClosetWeek() async {
    if (_isSnapping || !widget.snapToDay) return;
    _isSnapping = true;
    await Future.microtask(() => null);
    final snapPosition = ((_dayScrollController.offset) / (columnWidth*7)).round() * (columnWidth*7);
    _dayScrollController.animateTo(
      snapPosition,
      duration: widget.snapAnimationDuration,
      curve: widget.snapAnimationCurve,
    );
    _dayHeadingScrollController.animateTo(
      snapPosition,
      duration: widget.snapAnimationDuration,
      curve: widget.snapAnimationCurve,
    );
    _isSnapping = false;
  }

  Future _snapToNextWeek() async {
    if (_isSnapping || !widget.snapToDay) return;
    _isSnapping = true;
    await Future.microtask(() => null);
    final snapPosition = _dayScrollController.offset + (columnWidth*7);

    _dayScrollController.animateTo(
      snapPosition,
      duration: widget.snapAnimationDuration,
      curve: widget.snapAnimationCurve,
    );
    _dayHeadingScrollController.animateTo(
      snapPosition,
      duration: widget.snapAnimationDuration,
      curve: widget.snapAnimationCurve,
    );
    _isSnapping = false;
  }

  Future _snapToPrevWeek() async {
    if (_isSnapping || !widget.snapToDay) return;
    _isSnapping = true;
    await Future.microtask(() => null);
    final prevPosition = _dayScrollController.offset - (columnWidth*7);
    double snapPosition = prevPosition >= 0 ? prevPosition : 0;

    _dayScrollController.animateTo(
      snapPosition,
      duration: widget.snapAnimationDuration,
      curve: widget.snapAnimationCurve,
    );
    _dayHeadingScrollController.animateTo(
      snapPosition,
      duration: widget.snapAnimationDuration,
      curve: widget.snapAnimationCurve,
    );
    _isSnapping = false;
  }

  _updateVisibleDate() async {
    final date = controller.start.add(
      Duration(
        days: _dayHeadingScrollController.position.pixels ~/ columnWidth,
        hours: _timeScrollController.position.pixels ~/ controller.cellHeight,
      ),
    );
    if (date != controller.visibleDateStart) {
      controller.updateVisibleDate(date);
      setState(() {});
    }
  }


  Future _jumpTo(DateTime date) async {
    final datePosition =
        (date
            .difference(controller.start)
            .inDays) * columnWidth;
    final hourPosition =
        ((date.hour) * controller.cellHeight) - (controller.cellHeight / 2);
    await Future.wait([
      _dayScrollController.animateTo(
        datePosition,
        duration: widget.snapAnimationDuration,
        curve: widget.snapAnimationCurve,
      ),
      _timeScrollController.animateTo(
        hourPosition,
        duration: widget.snapAnimationDuration,
        curve: widget.snapAnimationCurve,
      ),
    ]);
  }
}
