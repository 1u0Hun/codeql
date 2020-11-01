/**
 * @name Uncaught Servlet Exception
 * @description Uncaught exceptions in a servlet could leave a system in an unexpected state, possibly resulting in denial-of-service attacks or the exposure of sensitive information disclosed in stack traces.
 * @kind path-problem
 * @id java/uncaught-servlet-exception
 * @tags security
 *       external/cwe-600
 */

import java
import semmle.code.java.dataflow.FlowSources
import semmle.code.java.dataflow.TaintTracking
import semmle.code.java.frameworks.Servlets
import semmle.code.xml.WebXML
import DataFlow::PathGraph

/** Holds if a given exception type is caught. */
private predicate exceptionIsCaught(TryStmt t, RefType exType) {
  exists(CatchClause cc, LocalVariableDeclExpr v |
    t.getACatchClause() = cc and
    cc.getVariable() = v and
    v.getType().(RefType).getASubtype*() = exType and // Detect the case that a subclass exception is thrown but its parent class is declared in the catch clause.
    not exists(
      ThrowStmt ts, ClassInstanceExpr cie // Catch and rethrow an exception without processing, e.g. catch (UnknownHostException uhex) {throw new IOException(uhex);}
    |
      ts.getEnclosingStmt() = cc.getBlock() and
      ts.getExpr() = cie and
      cie.getArgument(0) = v.getAnAccess()
    )
  )
}

/** Servlet methods of `javax.servlet.http.Servlet` and subtypes. */
private predicate isServletMethod(Callable c) {
  c.getDeclaringType() instanceof ServletClass and
  c.getNumberOfParameters() = 2 and
  c.getParameter(1).getType() instanceof ServletResponse and
  c.getName() in ["doGet", "doPost", "doPut", "doDelete", "doHead", "doOptions", "doTrace",
        "service"]
}

/** Holds if `web.xml` has an error page configured. */
private predicate hasErrorPage() {
  exists(WebErrorPage wep | wep.getPageLocation().getValue() != "")
}

/** Sink of uncaught exceptions, which shall be IO exceptions or runtime exceptions since other exception types must be explicitly caught. */
class UncaughtServletExceptionSink extends DataFlow::ExprNode {
  UncaughtServletExceptionSink() {
    exists(Method m, MethodAccess ma | ma.getMethod() = m |
      isServletMethod(ma.getEnclosingCallable()) and
      ma.getAnArgument() = this.getExpr() and
      not exists(TryStmt t |
        t.getBlock() = ma.getEnclosingStmt().getEnclosingStmt*() and
        exceptionIsCaught(t, m.getAThrownExceptionType())
      )
    )
  }
}

/** Taint configuration of uncaught exceptions caused by user provided data from `RemoteFlowSource` */
class UncaughtServletExceptionConfiguration extends TaintTracking::Configuration {
  UncaughtServletExceptionConfiguration() { this = "UncaughtServletException" }

  override predicate isSource(DataFlow::Node source) { source instanceof RemoteFlowSource }

  override predicate isSink(DataFlow::Node sink) { sink instanceof UncaughtServletExceptionSink }
}

from DataFlow::PathNode source, DataFlow::PathNode sink, UncaughtServletExceptionConfiguration c
where c.hasFlowPath(source, sink) and not hasErrorPage()
select sink.getNode(), source, sink, "$@ flows to here and can throw uncaught exception.",
  source.getNode(), "User-provided value"
