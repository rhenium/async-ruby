#include "ruby.h"
#include "ruby/vm_core.h"
#include "ruby/iseq.h"

// begin: proc.c (v2.3.0-preview1)
struct METHOD {
    const VALUE recv;
    const VALUE klass;
    const rb_method_entry_t * const me;
    /* for bound methods, `me' should be rb_callable_method_entry_t * */
};
// end: proc.c

static VALUE mAsync;
static VALUE cAsyncTask;

static rb_iseq_t *
transform(VALUE callable)
{
    VALUE old_iseqw_ary, new_iseqw_ary;
    VALUE old_iseqw, new_iseqw;

    old_iseqw = rb_funcall(rb_cISeq, rb_intern("of"), 1, callable);
    old_iseqw_ary = rb_funcall(old_iseqw, rb_intern("to_a"), 0);

    new_iseqw_ary = rb_funcall(mAsync, rb_intern("transform"), 1, old_iseqw_ary);
    new_iseqw = rb_iseq_load(new_iseqw_ary, 0, Qnil);

    return DATA_PTR(new_iseqw);
}

static VALUE
mod_async(VALUE klass, VALUE method_name)
{
    VALUE umethod;
    struct METHOD *data;
    rb_iseq_t *niseq;

    rb_frozen_class_p(klass);

    umethod = rb_funcall(klass, rb_intern("instance_method"), 1, method_name);
    data = (struct METHOD *)DATA_PTR(umethod); // UnboundMethod's DATA_PTR is (struct METHOD *)
    if (data->me->def->type != VM_METHOD_TYPE_ISEQ) {
        rb_raise(rb_eTypeError, "unsupported method type (only iseq supported)");
    }

    // 元の iseqptr が消えなかったり nseq が消えたりするような気もするけど知らない
    niseq = transform(umethod);
    *((rb_iseq_t **)&data->me->def->body.iseq.iseqptr) = niseq;

    return method_name;
}

// default behavior of async (doesn't accept Symbol)
// call-seq:
//      async { }
//      async Proc.new
static VALUE
kern_async(int argc, VALUE *argv, VALUE self)
{
    VALUE obj;
    rb_proc_t *proc;
    rb_iseq_t *niseq;

    rb_scan_args(argc, argv, "01", &obj);
    if (!NIL_P(obj)) {
        if (!rb_obj_is_proc(obj)) {
            rb_raise(rb_eTypeError, "wrong argument type (expected Proc)");
        }
    } else if (rb_block_given_p()) {
        obj = rb_block_proc();
    } else {
        rb_raise(rb_eArgError, "Proc or block is required");
    }

    proc = (rb_proc_t *)DATA_PTR(obj);

    // うーーー
    niseq = transform(obj);
    proc->block.iseq = niseq;

    return obj;
}

void
Init_ext(void)
{
    // async def method_a; end
    rb_define_private_method(rb_cModule, "async", mod_async, 1);
    // [].map &async { |args| await Task.new { } }
    rb_define_private_method(rb_mKernel, "async", kern_async, -1);

    mAsync = rb_define_module("Async");
    cAsyncTask = rb_define_class_under(mAsync, "Task", rb_cObject);
}
