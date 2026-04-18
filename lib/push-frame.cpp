#include <ecl/ecl.h>
#include <QtQml/QQmlProperty>
#include <QVariantList>
#include <QObject>

extern "C" {

int hecl_push_frame(cl_object l_vec, int count,
                    quintptr display_ptr, int cursor_row, int cursor_col,
                    double scroll_pixel_y) {
    QObject *display = reinterpret_cast<QObject *>(display_ptr);
    if (!display) return 0;

    QVariantList list;
    list.reserve(count);
    for (int i = 0; i < count; i++) {
        cl_object el = ecl_aref1(l_vec, i);
        if (el == ECL_T)       list.append(QVariant(true));
        else if (el == ECL_NIL) list.append(QVariant(false));
        else                    list.append(QVariant(static_cast<int>(fixint(el))));
    }

    // Set content first, then scroll position (animation triggers on scroll change)
    QQmlProperty::write(display, "frameData", QVariant::fromValue(list));
    QQmlProperty::write(display, "cursorRow", QVariant(cursor_row));
    QQmlProperty::write(display, "cursorCol", QVariant(cursor_col));

    // scroll_pixel_y is scroll-top in lines; multiply by cellH for pixels
    QVariant chv = QQmlProperty::read(display, "cellH");
    double ch = chv.isValid() ? chv.toDouble() : 17.0;
    QQmlProperty::write(display, "scrollPixelY", QVariant(scroll_pixel_y * ch));
    return 1;
}

}
