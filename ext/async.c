#include "ruby.h"
#include "ruby/vm_core.h"
#include "ruby/iseq.h"
#include <stdio.h>

// begin: proc.c (v2_3_0_preview1)
struct METHOD {
    const VALUE recv;
    const VALUE klass;
    const rb_method_entry_t * const me;
    /* for bound methods, `me' should be rb_callable_method_entry_t * */
};
// end: proc.c

VALUE mAsync;

static void
asyncify(VALUE umethod, rb_iseq_t *nseq)
{
    struct METHOD *data;
    const rb_method_definition_t *def;

    data = (struct METHOD *)DATA_PTR(umethod); // UnboundMethod's DATA_PTR is (struct METHOD *)
    def = data->me->def;

    if (def->type != VM_METHOD_TYPE_ISEQ) {
        rb_raise(rb_eTypeError, "unsupported method type (only iseq supported)");
    }

    // 元の iseqptr が消えなかったり nseq が突然消えたりするような気もするけど知らない
    RB_OBJ_WRITE(data->me, &def->body.iseq.iseqptr, nseq);
}

static rb_iseq_t *
iseq_from_iseqw(VALUE iseqw)
{
    return DATA_PTR(iseqw);
}

static VALUE
async_mod_async(VALUE klass, VALUE method_name)
{
    ID mid;
    VALUE umethod;
    VALUE old_iseqw, old_iseqw_ary;
    VALUE new_iseqw, new_iseqw_ary;
    
    rb_frozen_class_p(klass);

    mid = rb_check_id(&method_name);
    if (!mid) {
        rb_raise(rb_eTypeError, "invalid method");
    }

    umethod = rb_funcall(klass, rb_intern("instance_method"), 1, method_name);

    old_iseqw = rb_funcall(rb_cISeq, rb_intern("of"), 1, umethod);
    old_iseqw_ary = rb_funcall(old_iseqw, rb_intern("to_a"), 0);

    new_iseqw_ary = rb_funcall(mAsync, rb_intern("transform"), 1, old_iseqw_ary);
    new_iseqw = rb_iseq_load(new_iseqw_ary, 0, Qnil);

    asyncify(umethod, iseq_from_iseqw(new_iseqw));

    rb_funcall(klass, rb_intern("define_method"), 2, method_name, umethod);

    return method_name;
}

void
Init_ext(void)
{
    rb_define_private_method(rb_cModule, "async", async_mod_async, 1);
    mAsync = rb_define_module("Async");
}
