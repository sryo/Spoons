<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE xsl:stylesheet [
  <!ENTITY nbsp "&#160;"><!ENTITY copy "&#169;"><!ENTITY bullet "&#x25CF;">
]>
<xsl:stylesheet version="1.0" xmlns:xsl="http://www.w3.org/1999/XSL/Transform">
  <xsl:template match="/lsmd">
    <html>
      <head>
        <link rel="StyleSheet" href="doc2.css" type="text/css"/>
        <title>
          <xsl:for-each select="module">
            <xsl:choose>
              <xsl:when test="@friendlyname">
                <xsl:value-of select="@friendlyname"/>
              </xsl:when>
              <xsl:otherwise>
                <xsl:value-of select="concat(@basename,' ',@version)"/>
              </xsl:otherwise>
            </xsl:choose>
            <xsl:if test="position() != last()">
              <xsl:text>, </xsl:text>
            </xsl:if>
          </xsl:for-each>
        </title>
      </head><body>
	  <div class="entry">
	   <div class="docinfowrapper">
        <div class="docinfo">
          <h4>LSMD Document</h4>
		  <p>
          <dl><dt>lsmd version:</dt> <dd><xsl:value-of select="@spec"/></dd>
		  <dt>file version:</dt> <dd><xsl:value-of select="@version"/></dd>
<!--		  <dt>last modified:</dt> <dd><xsl:value-of select="@modified"/></dd>-->
		  </dl><xsl:choose>
              <xsl:when test="author">
                by <xsl:apply-templates select="author" mode="print"/>
              </xsl:when>
              <xsl:otherwise>author unknown.</xsl:otherwise>
            </xsl:choose>
            <xsl:if test="link">
              <br/>
              <ul>
                <xsl:apply-templates select="link" mode="list"/>
              </ul>
            </xsl:if>
          </p>
        </div></div>
        <xsl:apply-templates select="module" mode="doc"/>
      </div>
	</body></html>
  </xsl:template>
  <xsl:template name="section-header">
    <xsl:param name="title"/>
    <xsl:param name="id"/>
    <xsl:text>&#13;</xsl:text>
	<h4 class="section">
      <xsl:element name="a">
        <xsl:attribute name="name"><xsl:value-of select="$id"/></xsl:attribute>
        <xsl:value-of select="$title"/>
      </xsl:element>
	</h4>
  </xsl:template>
  <xsl:template match="author" mode="print">
    <xsl:if test="position() = last() and last() != 1">and </xsl:if>
    <xsl:choose>
      <xsl:when test="@email">
        <!-- we have an emal address -->
        <xsl:element name="a">
          <xsl:attribute name="href"><xsl:value-of select="concat('mailto:',@email)"/></xsl:attribute>
          <xsl:value-of select="text()"/>
        </xsl:element>
      </xsl:when>
      <xsl:otherwise>
        <!-- we don't have an email address -->
        <xsl:value-of select="text()"/>
      </xsl:otherwise>
    </xsl:choose>
    <xsl:if test="position() != last() and last() > 2">,</xsl:if>
    <xsl:if test="position() != last()">
      <xsl:text> </xsl:text>
    </xsl:if>
  </xsl:template>
  <xsl:template match="copyright" mode="nolink">
    <xsl:if test="position() = last() and last() != 1">and </xsl:if>
	<xsl:value-of select="@year"/>
    <xsl:text> </xsl:text>
	<xsl:value-of select="text()"/>
    <xsl:if test="position() != last() and last() > 2">,</xsl:if>
    <xsl:if test="position() != last()">
      <xsl:text> </xsl:text>
    </xsl:if>
  </xsl:template>
  
  
  <xsl:template match="link" mode="list">
    <li>
      <xsl:value-of select="@rel"/>: <xsl:element name="a">
        <xsl:attribute name="href"><xsl:value-of select="@href"/></xsl:attribute>
        <xsl:value-of select="."/>
      </xsl:element>
    </li>
  </xsl:template>
  <xsl:template match="hash" mode="list">
    <dt><xsl:value-of select="@method"/></dt><dd><xsl:value-of select="."/></dd>
  </xsl:template>
  <xsl:template match="module" mode="doc">
    <h2 class="module">
      <xsl:choose>
        <xsl:when test="@friendlyname">
          <xsl:value-of select="@friendlyname"/>
        </xsl:when>
        <xsl:otherwise>
          <xsl:value-of select="concat(@basename,' ',@version)"/>
        </xsl:otherwise>
      </xsl:choose>
    </h2>
	 <div class="summary">
      <p>
        <xsl:value-of select="concat(@basename,'-',@version)"/>
        <br/>by <xsl:choose>
          <xsl:when test="author">
            <xsl:apply-templates select="author" mode="print"/>
          </xsl:when>
          <xsl:otherwise>unknown</xsl:otherwise>
        </xsl:choose>
        <br/>Category: <xsl:value-of select="@category"/>
      </p>
      <p class="desc">
        <xsl:value-of select="documentation/description"/>
        <xsl:if test="link">
          <br/>
          <ul class="link">
            <xsl:apply-templates select="link" mode="list"/>
          </ul>
        </xsl:if>
      </p>
	 </div>
	<div>
<!-- TABLE OF CONTENTS -->
		<xsl:if test="not(//section/@id='toc')">
		  <xsl:call-template name="section-header">
			<xsl:with-param name="id">toc</xsl:with-param>
			<xsl:with-param name="title">Table of Contents</xsl:with-param>
		  </xsl:call-template>
		  <div>
			<xsl:apply-templates select="documentation" mode="toc"/>
		  </div>
		</xsl:if>
<!-- MAIN DOCUMENTATION -->
    <xsl:apply-templates select="documentation" mode="print"/>
<!-- HISTORY -->
		<xsl:if test="history and not(//section/@id='changes')">
		  <xsl:call-template name="section-header">
			<xsl:with-param name="id">changes</xsl:with-param>
			<xsl:with-param name="title">History</xsl:with-param>
		  </xsl:call-template>
		  <div class="section">
			<dl>
			  <xsl:apply-templates select="history/revision" mode="print"/>
			</dl>
		  </div>
		</xsl:if>
<!-- INDEX -->
    <xsl:if test="config//*[self::single or self::multiple] or control//bang or variables//var">
      <xsl:if test="not(//section/@id='index')">
        <xsl:call-template name="section-header">
          <xsl:with-param name="id">index</xsl:with-param>
          <xsl:with-param name="title">Index</xsl:with-param>
        </xsl:call-template>
		<div class="section">
        <table class="index">
          <colgroup width="*"/>
          <xsl:call-template name="index-section">
            <xsl:with-param name="title" select="'Configuration'"/>
            <xsl:with-param name="set" select="config//*[self::single or self::multiple]"/>
          </xsl:call-template>
          <xsl:call-template name="index-section">
            <xsl:with-param name="title" select="'Bang Commands'"/>
            <xsl:with-param name="set" select="control//bang"/>
          </xsl:call-template>
          <xsl:call-template name="index-section">
            <xsl:with-param name="title" select="'Variables'"/>
            <xsl:with-param name="set" select="variables//var"/>
          </xsl:call-template>
          <xsl:call-template name="index-section">
            <xsl:with-param name="title" select="'Tables'"/>
            <xsl:with-param name="set" select="//table"/>
          </xsl:call-template>
        </table>
		</div>
      </xsl:if>
    </xsl:if>
    <br/>
    <br/>
    <br/>
	<div class="footer">
		<xsl:text>Copyright &copy; </xsl:text>
		<xsl:apply-templates select="/lsmd/copyright" mode="nolink"/>
	</div>
	</div>
  </xsl:template>
  <xsl:template match="documentation" mode="toc">
    <ul class="toc">
      <xsl:for-each select="section">
        <li>
          <xsl:element name="a">
            <xsl:attribute name="href"><xsl:value-of select="concat('#',@id)"/></xsl:attribute>
            <xsl:value-of select="@name"/>
          </xsl:element>
        </li>
      </xsl:for-each>
      <xsl:if test="../history and not(//section/@id='changes')">
        <li>
          <xsl:element name="a">
            <xsl:attribute name="href">#changes</xsl:attribute>History</xsl:element>
        </li>
      </xsl:if>
      <xsl:if test="../config//*[self::single or self::multiple] or ../control//bang">
        <xsl:if test="not(//section/@id='index')">
          <li>
            <xsl:element name="a">
              <xsl:attribute name="href">#index</xsl:attribute>Index</xsl:element>
          </li>
        </xsl:if>
      </xsl:if>
    </ul>
  </xsl:template>
  <xsl:template match="documentation" mode="print">
    <xsl:choose>
      <xsl:when test="section">
        <xsl:for-each select="section">
          <xsl:variable name="section">
            <xsl:value-of select="concat(' ',@id,' ')"/>
          </xsl:variable>
          <xsl:call-template name="section-header">
            <xsl:with-param name="id">
              <xsl:value-of select="@id"/>
            </xsl:with-param>
            <xsl:with-param name="title" select="@name"/>
          </xsl:call-template>
          <div class="section">
            <xsl:apply-templates select="description" mode="print-section-header"/>
            <dl>
              <xsl:apply-templates select="../..//*[contains(concat(' ',@section,' '),$section)]" mode="print"/>
              <xsl:text> </xsl:text>
            </dl>
            <xsl:apply-templates select="description" mode="print-section-footer"/>
          </div>
        </xsl:for-each>
      </xsl:when>
      <xsl:otherwise>
        <xsl:if test="../..//single|../..//multiple">
          <xsl:call-template name="section-header">
            <xsl:with-param name="id">config</xsl:with-param>
            <xsl:with-param name="title">Configuration</xsl:with-param>
          </xsl:call-template>
          <div class="section">
            <dl>
              <xsl:apply-templates select="../..//single|../..//multiple" mode="print"/>
              <xsl:text> </xsl:text>
            </dl>
          </div>
        </xsl:if>
        <xsl:if test="../..//bang">
          <xsl:call-template name="section-header">
            <xsl:with-param name="id">control</xsl:with-param>
            <xsl:with-param name="title">Bang Commands</xsl:with-param>
          </xsl:call-template>
          <div class="section">
            <dl>
              <xsl:apply-templates select="../..//bang" mode="print"/>
              <xsl:text> </xsl:text>
            </dl>
          </div>
        </xsl:if>
        <xsl:if test="../..//var">
          <xsl:call-template name="section-header">
            <xsl:with-param name="id">vars</xsl:with-param>
            <xsl:with-param name="title">Variables</xsl:with-param>
          </xsl:call-template>
          <div class="section">
            <dl>
              <xsl:apply-templates select="../..//var" mode="print"/>
              <xsl:text> </xsl:text>
            </dl>
          </div>
        </xsl:if>
      </xsl:otherwise>
    </xsl:choose>
  </xsl:template>
  <xsl:template match="description" mode="print-section-header">
    <xsl:if test="position()=1">
      <xsl:apply-templates select="." mode="print-desc"/>
    </xsl:if>
  </xsl:template>
  <xsl:template match="description" mode="print-section-footer">
    <xsl:if test="position()=2">
      <xsl:apply-templates select="." mode="print-desc"/>
    </xsl:if>
  </xsl:template>

<!-- the comment of truth -->

  <xsl:key name="prefix" match="key" use="@id"/>
  <xsl:template match="multiple" mode="print">
    <dt class="definition">
      <xsl:element name="a">
        <xsl:attribute name="name"><xsl:call-template name="anchor-name"><xsl:with-param name="link"><xsl:choose><xsl:when test="@star='false'"/><xsl:otherwise>*</xsl:otherwise></xsl:choose><xsl:for-each select="ancestor-or-self::*/@prefix"><xsl:choose><xsl:when test="key('prefix',.)/@default"><xsl:value-of select="key('prefix',.)/@default"/></xsl:when><xsl:otherwise><xsl:value-of select="key('prefix',.)/@id"/></xsl:otherwise></xsl:choose></xsl:for-each><xsl:value-of select="@name"/></xsl:with-param></xsl:call-template></xsl:attribute>
        <xsl:choose>
          <xsl:when test="@star='false'"/>
          <xsl:otherwise>*</xsl:otherwise>
        </xsl:choose>
        <xsl:for-each select="ancestor-or-self::*/@prefix">
          <xsl:choose>
            <xsl:when test="key('prefix',.)/@default">
              <xsl:value-of select="key('prefix',.)/@default"/>
            </xsl:when>
            <xsl:otherwise>
              <span class="prefix">
                <xsl:value-of select="key('prefix',.)/@id"/>
              </span>
            </xsl:otherwise>
          </xsl:choose>
        </xsl:for-each>
        <xsl:value-of select="@name"/>
      </xsl:element>
      <xsl:apply-templates select="child::*" mode="params"/>
    </dt>
    <xsl:if test="description">
      <dd class="cmddoc">
        <xsl:apply-templates select="description" mode="print-desc"/>
      </dd>
    </xsl:if>
  </xsl:template>
  <xsl:template match="single" mode="print">
    <xsl:element name="dt">
      <xsl:if test="description">
        <xsl:attribute name="class">command</xsl:attribute>
      </xsl:if>
      <xsl:if test="not(description)">
        <xsl:attribute name="class">command-short</xsl:attribute>
      </xsl:if>
      <xsl:element name="a">
        <xsl:attribute name="name"><xsl:call-template name="anchor-name"><xsl:with-param name="link"><xsl:for-each select="ancestor-or-self::*/@prefix"><xsl:choose><xsl:when test="key('prefix',.)/@default"><xsl:value-of select="key('prefix',.)/@default"/></xsl:when><xsl:otherwise><span class="prefix"><xsl:value-of select="key('prefix',.)/@id"/></span></xsl:otherwise></xsl:choose></xsl:for-each><xsl:value-of select="@name"/></xsl:with-param></xsl:call-template></xsl:attribute>
        <xsl:for-each select="ancestor-or-self::*/@prefix">
          <xsl:choose>
            <xsl:when test="key('prefix',.)/@default">
              <xsl:value-of select="key('prefix',.)/@default"/>
            </xsl:when>
            <xsl:otherwise>
              <span class="prefix">
                <xsl:value-of select="key('prefix',.)/@id"/>
              </span>
            </xsl:otherwise>
          </xsl:choose>
        </xsl:for-each>
        <xsl:value-of select="@name"/>
      </xsl:element>
      <xsl:apply-templates select="child::*" mode="params"/>
    </xsl:element>
    <xsl:if test="description">
      <dd class="cmddoc">
        <xsl:apply-templates select="description" mode="print-desc"/>
      </dd>
    </xsl:if>
  </xsl:template>
  <xsl:template match="bang" mode="print">
    <dt class="bang">
      <xsl:element name="a">
        <xsl:attribute name="name"><xsl:call-template name="anchor-name"><xsl:with-param name="link">!<xsl:for-each select="ancestor-or-self::*/@prefix"><xsl:choose><xsl:when test="key('prefix',.)/@default"><xsl:value-of select="key('prefix',.)/@default"/></xsl:when><xsl:otherwise><span class="prefix"><xsl:value-of select="key('prefix',.)/@id"/></span></xsl:otherwise></xsl:choose></xsl:for-each><xsl:value-of select="@name"/></xsl:with-param></xsl:call-template></xsl:attribute>!<xsl:for-each select="ancestor-or-self::*/@prefix">
          <xsl:choose>
            <xsl:when test="key('prefix',.)/@default">
              <xsl:value-of select="key('prefix',.)/@default"/>
            </xsl:when>
            <xsl:otherwise>
              <span class="prefix">
                <xsl:value-of select="key('prefix',.)/@id"/>
              </span>
            </xsl:otherwise>
          </xsl:choose>
        </xsl:for-each>
        <xsl:value-of select="@name"/>
      </xsl:element>
      <xsl:apply-templates select="child::*" mode="params"/>
    </dt>
    <xsl:if test="description">
      <dd class="cmddoc">
        <xsl:apply-templates select="description" mode="print-desc"/>
      </dd>
    </xsl:if>
  </xsl:template>
  
  <xsl:template match="var" mode="print">
    <xsl:element name="dt">
      <xsl:if test="description">
        <xsl:attribute name="class">var</xsl:attribute>
      </xsl:if>
      <xsl:if test="not(description)">
        <xsl:attribute name="class">var-short</xsl:attribute>
      </xsl:if>
      <xsl:element name="a">
        <xsl:attribute name="name">
          <xsl:call-template name="anchor-name">
            <xsl:with-param name="link">
              <xsl:for-each select="ancestor-or-self::*/@prefix">
                <xsl:choose>
                  <xsl:when test="key('prefix',.)/@default">
                    <xsl:value-of select="key('prefix',.)/@default"/>
                  </xsl:when>
                  <xsl:otherwise>
                    <span class="prefix"><xsl:value-of select="key('prefix',.)/@id"/></span>
                  </xsl:otherwise>
                </xsl:choose>
              </xsl:for-each>
              <xsl:value-of select="@name"/>
            </xsl:with-param>
          </xsl:call-template>
        </xsl:attribute>
        <xsl:choose>
          <xsl:when test="ancestor-or-self::*/@delim-begin">
            <xsl:value-of select="ancestor-or-self::*/@delim-begin"/>
          </xsl:when>
          <xsl:otherwise><xsl:text>$</xsl:text></xsl:otherwise>
        </xsl:choose>
        <xsl:for-each select="ancestor-or-self::*/@prefix">
          <xsl:choose>
            <xsl:when test="key('prefix',.)/@default">
              <xsl:value-of select="key('prefix',.)/@default"/>
            </xsl:when>
            <xsl:otherwise>
              <span class="prefix">
                <xsl:value-of select="key('prefix',.)/@id"/>
              </span>
            </xsl:otherwise>
          </xsl:choose>
        </xsl:for-each>
        <xsl:value-of select="@name"/>
        <xsl:choose>
          <xsl:when test="ancestor-or-self::*/@delim-end">
            <xsl:value-of select="ancestor-or-self::*/@delim-end"/>
          </xsl:when>
          <xsl:otherwise><xsl:text>$</xsl:text></xsl:otherwise>
        </xsl:choose>
      </xsl:element>
      <xsl:apply-templates select="child::*" mode="params"/>
    </xsl:element>
    <xsl:if test="description">
      <dd class="cmddoc">
        <xsl:apply-templates select="description" mode="print-desc"/>
      </dd>
    </xsl:if>
  </xsl:template>

  <xsl:template match="group" mode="print">
    <xsl:apply-templates select="*" mode="print"/>
    <xsl:if test="description">
      <dd class="grpdoc">
        <xsl:apply-templates select="description" mode="print-desc"/>
      </dd>
    </xsl:if>
  </xsl:template>
  <xsl:template name="anchor-name">
    <xsl:param name="link"/>
    <xsl:choose>
      <xsl:when test="starts-with($link,'*')">
<!-- not enough for non-ascii case conversion, but I don't care. -->
        <xsl:value-of select="concat('star_',translate(substring($link,2),'ABCDEFGHIJKLMNOPQRSTUVWXYZ','abcdefghijklmnopqrstuvwxyz'))"/>
      </xsl:when>
      <xsl:when test="starts-with($link,'!')">
        <xsl:value-of select="concat('bang_',translate(substring($link,2),'ABCDEFGHIJKLMNOPQRSTUVWXYZ','abcdefghijklmnopqrstuvwxyz'))"/>
      </xsl:when>
      <xsl:otherwise>
        <xsl:value-of select="translate($link,'ABCDEFGHIJKLMNOPQRSTUVWXYZ','abcdefghijklmnopqrstuvwxyz')"/>
      </xsl:otherwise>
    </xsl:choose>
  </xsl:template>
  <xsl:template match="p" mode="print">
   <!-- some browsers have baggage preventing p nesting -->
    <div class="para">
      <xsl:apply-templates select="."/>
    </div>
  </xsl:template>
  <xsl:template match="example" mode="print">
    <div class="example">
      <xsl:apply-templates select="."/>
    </div>
  </xsl:template>
  <xsl:template match="table" mode="print">
    <xsl:element name="a">
      <xsl:attribute name="name"><xsl:value-of select="@id"/></xsl:attribute>
      <xsl:if test="@caption">
        <div class="table-caption"><xsl:value-of select="@caption"/></div>
      </xsl:if>
      <dl class="table">
      <xsl:apply-templates select="item" mode="print-table"/>
      </dl>
    </xsl:element>
  </xsl:template>
  <xsl:template match="item" mode="print-table">
    <dt><xsl:value-of select="@name"/></dt>
    <dd><xsl:apply-templates select="."/></dd>
  </xsl:template>
  <xsl:template match="code">
    <xsl:choose>
      <xsl:when test="contains(.,'&#10;')">
        <!--If the code block contains a newline, preserve all whitespace.-->
        <pre class="code">
          <xsl:apply-templates select="." mode="in-code"/>
        </pre>
      </xsl:when>
      <xsl:otherwise>
        <!--Otherwise collapse it, so code can be used inline.-->
        <tt class="code">
          <xsl:apply-templates select="." mode="in-code"/>
        </tt>
      </xsl:otherwise>
    </xsl:choose>
  </xsl:template>
  <xsl:template match="xref" mode="in-code">
    <xsl:choose>
      <!-- @iscode is meaningless inside a code element -->
      <xsl:when test="@link">
        <span class="xref">
          <xsl:element name="a">
            <xsl:attribute name="href">#<xsl:call-template name="anchor-name">
				<xsl:with-param name="link"><xsl:value-of select="@link"/></xsl:with-param>
			</xsl:call-template></xsl:attribute>
            <xsl:attribute name="title"><xsl:value-of select="@link"/></xsl:attribute>
            <xsl:value-of select="."/>
          </xsl:element>
        </span>
      </xsl:when>
      <xsl:otherwise>
        <tt class="xref">
          <xsl:element name="a">
            <xsl:attribute name="href">#<xsl:call-template name="anchor-name">
				<xsl:with-param name="link"><xsl:value-of select="."/></xsl:with-param>
			</xsl:call-template></xsl:attribute>
            <xsl:value-of select="."/>
          </xsl:element>
        </tt>
      </xsl:otherwise>
    </xsl:choose>
  </xsl:template>
  <xsl:template match="xref">
    <xsl:choose>
      <xsl:when test="@link and @iscode='true'">
        <tt class="xref">
          <xsl:element name="a">
            <xsl:attribute name="href">#<xsl:call-template name="anchor-name">
				<xsl:with-param name="link"><xsl:value-of select="@link"/></xsl:with-param>
			</xsl:call-template></xsl:attribute>
            <xsl:attribute name="title"><xsl:value-of select="@link"/></xsl:attribute>
            <xsl:value-of select="."/>
          </xsl:element>
        </tt>
      </xsl:when>
      <xsl:when test="@link">
        <span class="xref">
          <xsl:element name="a">
            <xsl:attribute name="href">#<xsl:call-template name="anchor-name">
				<xsl:with-param name="link"><xsl:value-of select="@link"/></xsl:with-param>
			</xsl:call-template></xsl:attribute>
            <xsl:attribute name="title"><xsl:value-of select="@link"/></xsl:attribute>
            <xsl:value-of select="."/>
          </xsl:element>
        </span>
      </xsl:when>
      <xsl:when test="@iscode='false'">
        <span class="xref">
          <xsl:element name="a">
            <xsl:attribute name="href">#<xsl:call-template name="anchor-name">
				<xsl:with-param name="link"><xsl:value-of select="."/></xsl:with-param>
			</xsl:call-template></xsl:attribute>
            <xsl:value-of select="."/>
          </xsl:element>
        </span>
      </xsl:when>
      <xsl:otherwise>
        <tt class="xref">
          <xsl:element name="a">
            <xsl:attribute name="href">#<xsl:call-template name="anchor-name">
				<xsl:with-param name="link"><xsl:value-of select="."/></xsl:with-param>
			</xsl:call-template></xsl:attribute>
            <xsl:value-of select="."/>
          </xsl:element>
        </tt>
      </xsl:otherwise>
    </xsl:choose>
  </xsl:template>
  <xsl:template match="strong">
    <strong><xsl:apply-templates select="text()"/></strong>
  </xsl:template>
  <xsl:template match="em">
    <em><xsl:apply-templates select="."/></em>
  </xsl:template>

  <xsl:template match="multiple" mode="summary">
    <li>
      <xsl:choose>
        <xsl:when test="@star='false'"/>
        <xsl:otherwise>*</xsl:otherwise>
      </xsl:choose>
      <xsl:for-each select="ancestor-or-self::*/@prefix">
        <xsl:choose>
          <xsl:when test="key('prefix',.)/@default">
            <xsl:value-of select="key('prefix',.)/@default"/>
          </xsl:when>
          <xsl:otherwise>
            <span class="prefix">
              <xsl:value-of select="key('prefix',.)/@id"/>
            </span>
          </xsl:otherwise>
        </xsl:choose>
      </xsl:for-each>
      <xsl:value-of select="@name"/>
      <xsl:apply-templates select="child::*" mode="params"/>
    </li>
  </xsl:template>
  <xsl:template match="single" mode="summary">
    <li>
      <xsl:for-each select="ancestor-or-self::*/@prefix">
        <xsl:choose>
          <xsl:when test="key('prefix',.)/@default">
            <xsl:value-of select="key('prefix',.)/@default"/>
          </xsl:when>
          <xsl:otherwise>
            <span class="prefix">
              <xsl:value-of select="key('prefix',.)/@id"/>
            </span>
          </xsl:otherwise>
        </xsl:choose>
      </xsl:for-each>
      <xsl:value-of select="@name"/>
      <xsl:apply-templates select="child::*" mode="params"/>
    </li>
  </xsl:template>
  <xsl:template match="bang" mode="summary">
    <li>!<xsl:for-each select="ancestor-or-self::*/@prefix">
        <xsl:choose>
          <xsl:when test="key('prefix',.)/@default">
            <xsl:value-of select="key('prefix',.)/@default"/>
          </xsl:when>
          <xsl:otherwise>
            <span class="prefix">
              <xsl:value-of select="key('prefix',.)/@id"/>
            </span>
          </xsl:otherwise>
        </xsl:choose>
      </xsl:for-each>
      <xsl:value-of select="@name"/>
      <xsl:apply-templates select="child::*" mode="params"/>
    </li>
  </xsl:template>
  <xsl:key name="prefix" match="key" use="@id"/>
  <xsl:template match="action" mode="params">
    <xsl:text> </xsl:text>
    <xsl:element name="small">
      <xsl:attribute name="class"><xsl:choose><xsl:when test="@optional='true'">oparam</xsl:when><xsl:otherwise>param</xsl:otherwise></xsl:choose></xsl:attribute>ACTION</xsl:element>
  </xsl:template>
  <xsl:template match="bool" mode="params">
    <xsl:text> </xsl:text>
    <xsl:element name="small">
      <xsl:attribute name="class"><xsl:choose><xsl:when test="@optional='true'">oparam</xsl:when><xsl:otherwise>param</xsl:otherwise></xsl:choose></xsl:attribute>BOOL</xsl:element>
  </xsl:template>
  <xsl:template match="color" mode="params">
    <xsl:text> </xsl:text>
    <xsl:element name="small">
      <xsl:attribute name="class"><xsl:choose><xsl:when test="@optional='true'">oparam</xsl:when><xsl:otherwise>param</xsl:otherwise></xsl:choose></xsl:attribute>COLOR</xsl:element>
  </xsl:template>
  <xsl:template match="coordinate" mode="params">
    <xsl:text> </xsl:text>
    <xsl:element name="small">
      <xsl:attribute name="class"><xsl:choose><xsl:when test="@optional='true'">oparam</xsl:when><xsl:otherwise>param</xsl:otherwise></xsl:choose></xsl:attribute>COORD</xsl:element>
  </xsl:template>
  <xsl:template match="file" mode="params">
    <xsl:text> </xsl:text>
    <xsl:element name="small">
      <xsl:attribute name="class"><xsl:choose><xsl:when test="@optional='true'">oparam</xsl:when><xsl:otherwise>param</xsl:otherwise></xsl:choose></xsl:attribute>FILE</xsl:element>
  </xsl:template>
  <xsl:template match="flags" mode="params">
    <xsl:text> </xsl:text>
    <xsl:element name="small">
      <xsl:attribute name="class"><xsl:choose><xsl:when test="@optional='true'">oparam</xsl:when><xsl:otherwise>param</xsl:otherwise></xsl:choose></xsl:attribute>#FLAGS</xsl:element>
  </xsl:template>
  <xsl:template match="folder" mode="params">
    <xsl:text> </xsl:text>
    <xsl:element name="small">
      <xsl:attribute name="class"><xsl:choose><xsl:when test="@optional='true'">oparam</xsl:when><xsl:otherwise>param</xsl:otherwise></xsl:choose></xsl:attribute>FOLDER</xsl:element>
  </xsl:template>
  <xsl:template match="font" mode="params">
    <xsl:text> </xsl:text>
    <xsl:element name="small">
      <xsl:attribute name="class"><xsl:choose><xsl:when test="@optional='true'">oparam</xsl:when><xsl:otherwise>param</xsl:otherwise></xsl:choose></xsl:attribute>FONT</xsl:element>
  </xsl:template>
  <xsl:template match="image" mode="params">
    <xsl:text> </xsl:text>
    <xsl:element name="small">
      <xsl:attribute name="class"><xsl:choose><xsl:when test="@optional='true'">oparam</xsl:when><xsl:otherwise>param</xsl:otherwise></xsl:choose></xsl:attribute>IMAGE</xsl:element>
  </xsl:template>
  <xsl:template match="integer" mode="params">
    <xsl:text> </xsl:text>
    <xsl:element name="small">
      <xsl:attribute name="class"><xsl:choose><xsl:when test="@optional='true'">oparam</xsl:when><xsl:otherwise>param</xsl:otherwise></xsl:choose></xsl:attribute>INT</xsl:element>
  </xsl:template>
  <xsl:template match="option" mode="params">
    <xsl:text> </xsl:text>
    <xsl:element name="small">
      <xsl:attribute name="class"><xsl:choose><xsl:when test="@optional='true'">oparam</xsl:when><xsl:otherwise>param</xsl:otherwise></xsl:choose></xsl:attribute>OPTION</xsl:element>
  </xsl:template>
  <xsl:template match="key" mode="params">
    <xsl:text> </xsl:text>
    <xsl:element name="small">
      <xsl:attribute name="class"><xsl:choose><xsl:when test="@optional='true'">oparam</xsl:when><xsl:otherwise>param</xsl:otherwise></xsl:choose></xsl:attribute>NAME</xsl:element>
  </xsl:template>
  <xsl:template match="sound" mode="params">
    <xsl:text> </xsl:text>
    <xsl:element name="small">
      <xsl:attribute name="class"><xsl:choose><xsl:when test="@optional='true'">oparam</xsl:when><xsl:otherwise>param</xsl:otherwise></xsl:choose></xsl:attribute>SOUND</xsl:element>
  </xsl:template>
  <xsl:template match="string" mode="params">
    <xsl:text> </xsl:text>
    <xsl:element name="small">
      <xsl:attribute name="class"><xsl:choose><xsl:when test="@optional='true'">oparam</xsl:when><xsl:otherwise>param</xsl:otherwise></xsl:choose></xsl:attribute>STRING</xsl:element>
  </xsl:template>
  <xsl:template match="url" mode="params">
    <xsl:text> </xsl:text>
    <xsl:element name="small">
      <xsl:attribute name="class"><xsl:choose><xsl:when test="@optional='true'">oparam</xsl:when><xsl:otherwise>param</xsl:otherwise></xsl:choose></xsl:attribute>URL</xsl:element>
  </xsl:template>
  <xsl:template match="repeat" mode="params">
    <xsl:text> </xsl:text>
    <span class="repeat">
      <xsl:apply-templates select="child::*" mode="params"/>
      <span class="again">
        <xsl:apply-templates select="child::*" mode="params"/>
      </span>...</span>
  </xsl:template>
  <xsl:template match="description" mode="params"/>
  <xsl:template match="description" mode="print"/>
  <xsl:template match="description" mode="print-desc">
    <xsl:apply-templates select="*" mode="print"/>
  </xsl:template>
  <xsl:template match="fixed" mode="changes">
    <xsl:text>&#13;</xsl:text>
    <li class="fixed">
      &bullet; <xsl:apply-templates select="."/>
    </li>
  </xsl:template>
  <xsl:template match="added" mode="changes">
    <xsl:text>&#13;</xsl:text>
    <li class="added">
      &bullet; <xsl:apply-templates select="."/>
    </li>
  </xsl:template>
  <xsl:template match="changed" mode="changes">
    <xsl:text>&#13;</xsl:text>
    <li class="changed">
      &bullet; <xsl:apply-templates select="."/>
    </li>
  </xsl:template>
  <xsl:template match="removed" mode="changes">
    <xsl:text>&#13;</xsl:text>
    <li class="removed">
      &bullet; <xsl:apply-templates select="."/>
    </li>
  </xsl:template>
  <xsl:template match="revision" mode="print">
    <xsl:text>&#13;</xsl:text>
    <dt class="revt">
      <xsl:if test="@date">
        <xsl:value-of select="@date"/>
        <xsl:text> </xsl:text>
      </xsl:if>
      <xsl:if test="@version"> version <xsl:value-of select="@version"/>
      </xsl:if>
      <xsl:if test="@by"> by <xsl:value-of select="@by"/>
      </xsl:if>
    </dt>
    <dd class="revd">
      <ul class="revision">
        <xsl:apply-templates select="child::*" mode="changes"/>
      </ul>
    </dd>
  </xsl:template>
  <xsl:template name="index-section">
    <xsl:param name="set"/>
    <xsl:param name="title"/>
    <xsl:variable name="a">
      <xsl:value-of select="(count($set)*1+2) div 3"/>
    </xsl:variable>
    <xsl:variable name="b">
      <xsl:value-of select="(count($set)*2+1) div 3"/>
    </xsl:variable>
    <xsl:if test="count($set)&gt;0">
      <tr>
        <th colspan="3">
          <xsl:value-of select="$title"/>
        </th>
      </tr>
      <tr>
        <td>
          <xsl:for-each select="$set">
          <!-- Most xslt parsers won't accept this, but when it does
               work, this is really what I want to sort with.
            <xsl:variable name="fullname">
              <xsl:for-each select="ancestor-or-self::*/@prefix">
                <xsl:choose>
                  <xsl:when test="key('prefix',.)/@default">
                    <xsl:value-of select="key('prefix',.)/@default"/>
                  </xsl:when>
                  <xsl:otherwise>
                    <xsl:value-of select="key('prefix',.)/@id"/>
                  </xsl:otherwise>
                </xsl:choose>
              </xsl:for-each>
              <xsl:value-of select="@name"/>
            </xsl:variable>
            <xsl:sort select="string($fullname)"/>
            -->
            <xsl:sort select="@name"/>
            <xsl:if test="position()&lt;=$a">
              <xsl:apply-templates select="." mode="index"/>
            </xsl:if>
          </xsl:for-each>
        </td>
        <td>
          <xsl:for-each select="$set">
            <xsl:sort select="@name"/>
            <xsl:if test="position()&gt;$a and position()&lt;=$b">
              <xsl:apply-templates select="." mode="index"/>
            </xsl:if>
          </xsl:for-each>
        </td>
        <td>
          <xsl:for-each select="$set">
            <xsl:sort select="@name"/>
            <xsl:if test="position()&gt;$b">
              <xsl:apply-templates select="." mode="index"/>
            </xsl:if>
          </xsl:for-each>
        </td>
      </tr>
    </xsl:if>
  </xsl:template>
  <xsl:template match="multiple" mode="index">
    <xsl:element name="a">
      <xsl:attribute name="href">#<xsl:call-template name="anchor-name"><xsl:with-param name="link"><xsl:choose><xsl:when test="@star='false'"/><xsl:otherwise>*</xsl:otherwise></xsl:choose><xsl:for-each select="ancestor-or-self::*/@prefix"><xsl:choose><xsl:when test="key('prefix',.)/@default"><xsl:value-of select="key('prefix',.)/@default"/></xsl:when><xsl:otherwise><xsl:value-of select="key('prefix',.)/@id"/></xsl:otherwise></xsl:choose></xsl:for-each><xsl:value-of select="@name"/></xsl:with-param></xsl:call-template></xsl:attribute>
      <xsl:choose>
        <xsl:when test="@star='false'"/>
        <xsl:otherwise>*</xsl:otherwise>
      </xsl:choose>
      <xsl:for-each select="ancestor-or-self::*/@prefix">
        <xsl:choose>
          <xsl:when test="key('prefix',.)/@default">
            <xsl:value-of select="key('prefix',.)/@default"/>
          </xsl:when>
          <xsl:otherwise>
            <span class="prefix">
              <xsl:value-of select="key('prefix',.)/@id"/>
            </span>
          </xsl:otherwise>
        </xsl:choose>
      </xsl:for-each>
      <xsl:value-of select="@name"/>
    </xsl:element>
    <br/>
  </xsl:template>
  <xsl:template match="single" mode="index">
    <xsl:element name="a">
      <xsl:attribute name="href">#<xsl:call-template name="anchor-name"><xsl:with-param name="link"><xsl:for-each select="ancestor-or-self::*/@prefix"><xsl:choose><xsl:when test="key('prefix',.)/@default"><xsl:value-of select="key('prefix',.)/@default"/></xsl:when><xsl:otherwise><xsl:value-of select="key('prefix',.)/@id"/></xsl:otherwise></xsl:choose></xsl:for-each><xsl:value-of select="@name"/></xsl:with-param></xsl:call-template></xsl:attribute>
      <xsl:for-each select="ancestor-or-self::*/@prefix">
        <xsl:choose>
          <xsl:when test="key('prefix',.)/@default">
            <xsl:value-of select="key('prefix',.)/@default"/>
          </xsl:when>
          <xsl:otherwise>
            <span class="prefix">
              <xsl:value-of select="key('prefix',.)/@id"/>
            </span>
          </xsl:otherwise>
        </xsl:choose>
      </xsl:for-each>
      <xsl:value-of select="@name"/>
    </xsl:element>
    <br/>
  </xsl:template>
  <xsl:template match="bang" mode="index">
    <xsl:element name="a">
      <xsl:attribute name="href">#<xsl:call-template name="anchor-name"><xsl:with-param name="link">!<xsl:for-each select="ancestor-or-self::*/@prefix"><xsl:choose><xsl:when test="key('prefix',.)/@default"><xsl:value-of select="key('prefix',.)/@default"/></xsl:when><xsl:otherwise><span class="prefix"><xsl:value-of select="key('prefix',.)/@id"/></span></xsl:otherwise></xsl:choose></xsl:for-each><xsl:value-of select="@name"/></xsl:with-param></xsl:call-template></xsl:attribute>!<xsl:for-each select="ancestor-or-self::*/@prefix">
        <xsl:choose>
          <xsl:when test="key('prefix',.)/@default">
            <xsl:value-of select="key('prefix',.)/@default"/>
          </xsl:when>
          <xsl:otherwise>
            <span class="prefix">
              <xsl:value-of select="key('prefix',.)/@id"/>
            </span>
          </xsl:otherwise>
        </xsl:choose>
      </xsl:for-each>
      <xsl:value-of select="@name"/>
    </xsl:element>
    <br/>
  </xsl:template>
  <xsl:template match="var" mode="index">
    <xsl:element name="a">
      <xsl:attribute name="href">#<xsl:call-template name="anchor-name"><xsl:with-param name="link"><xsl:for-each select="ancestor-or-self::*/@prefix"><xsl:choose><xsl:when test="key('prefix',.)/@default"><xsl:value-of select="key('prefix',.)/@default"/></xsl:when><xsl:otherwise><span class="prefix"><xsl:value-of select="key('prefix',.)/@id"/></span></xsl:otherwise></xsl:choose></xsl:for-each><xsl:value-of select="@name"/></xsl:with-param></xsl:call-template></xsl:attribute>
      <xsl:choose>
        <xsl:when test="ancestor-or-self::*/@delim-begin">
          <xsl:value-of select="ancestor-or-self::*/@delim-begin"/>
        </xsl:when>
        <xsl:otherwise><xsl:text>$</xsl:text></xsl:otherwise>
      </xsl:choose>
      <xsl:for-each select="ancestor-or-self::*/@prefix">
        <xsl:choose>
          <xsl:when test="key('prefix',.)/@default">
            <xsl:value-of select="key('prefix',.)/@default"/>
          </xsl:when>
          <xsl:otherwise>
            <span class="prefix">
              <xsl:value-of select="key('prefix',.)/@id"/>
            </span>
          </xsl:otherwise>
        </xsl:choose>
      </xsl:for-each>
      <xsl:value-of select="@name"/>
      <xsl:choose>
        <xsl:when test="ancestor-or-self::*/@delim-end">
          <xsl:value-of select="ancestor-or-self::*/@delim-end"/>
        </xsl:when>
        <xsl:otherwise><xsl:text>$</xsl:text></xsl:otherwise>
      </xsl:choose>
    </xsl:element>
    <br/>
  </xsl:template>
  <xsl:template match="table" mode="index">
    <xsl:element name="a">
      <xsl:attribute name="href">#<xsl:call-template name="anchor-name"><xsl:with-param name="link"><xsl:value-of select="@id"/></xsl:with-param></xsl:call-template></xsl:attribute>
      <xsl:choose>
        <xsl:when test="@caption">
          <xsl:value-of select="@caption"/>
        </xsl:when>
        <xsl:otherwise>
          <xsl:value-of select="@id"/>
        </xsl:otherwise>
      </xsl:choose>
    </xsl:element>
    <br/>
  </xsl:template>
  <xsl:preserve-space elements="code"/>
</xsl:stylesheet>

