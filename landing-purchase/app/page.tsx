import Nav from "@/components/Nav";
import Hero from "@/components/Hero";
import ProductShowcase from "@/components/ProductShowcase";
import HowItWorks from "@/components/HowItWorks";
import TwoTabExplainer from "@/components/TwoTabExplainer";
import ValuePillars from "@/components/ValuePillars";
import Pricing from "@/components/Pricing";
import FAQ from "@/components/FAQ";
import Footer from "@/components/Footer";

export default function Home() {
  return (
    <main>
      <Nav />
      <Hero />
      <ProductShowcase />
      <HowItWorks />
      <TwoTabExplainer />
      <ValuePillars />
      <Pricing />
      <FAQ />
      <Footer />
    </main>
  );
}
